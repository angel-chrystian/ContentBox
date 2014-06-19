﻿/**
********************************************************************************
ContentBox - A Modular Content Platform
Copyright 2012 by Luis Majano and Ortus Solutions, Corp
www.gocontentbox.org | www.luismajano.com | www.ortussolutions.com
********************************************************************************
Apache License, Version 2.0

Copyright Since [2012] [Luis Majano and Ortus Solutions,Corp]

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
********************************************************************************
* Page service for contentbox
*/
component extends="ContentService" singleton{

	// Inject generic content service
	property name="contentService" inject="id:ContentService@cb";

	/**
	* Constructor
	*/
	PageService function init(){
		// init it
		super.init(entityName="cbPage", useQueryCaching=true);

		return this;
	}

	/**
	* Save a page and do necessary updates
	* @page.hint The page to save or update
	* @originalSlug.hint If an original slug is passed, then we need to update hierarchy slugs.
	*/
	function savePage( required any page, string originalSlug="" ) transactional{

		// Verify uniqueness of slug
		if( !contentService.isSlugUnique( slug=arguments.page.getSlug(), contentID=arguments.page.getContentID() ) ){
			// make slug unique
			arguments.page.setSlug( getUniqueSlugHash( arguments.page.getSlug() ) );
		}

		// Save the target page
		save( entity=arguments.page, transactional=false );

		// Update all affected child pages if any on slug updates, much like nested set updates its nodes, we update our slugs
		if( structKeyExists( arguments, "originalSlug" ) AND len( arguments.originalSlug ) ){
			var pagesInNeed = newCriteria().like( "slug", "#arguments.originalSlug#/%" ).list();
			for( var thisPage in pagesInNeed ){
				thisPage.setSlug( replaceNoCase( thisPage.getSlug(), arguments.originalSlug, arguments.page.getSlug() ) );
				save( entity=thisPage, transactional=false );
			}
		}

		return this;
	}

	/**
	* page search returns struct with keys [pages,count]
	* @parent.hint If empty, then looks for empty parent nodes. If you do not want to attach it, send as null
	*/
	struct function search(search="",isPublished,author,parent,category,max=0,offset=0,sortOrder="title asc",boolean searchActiveContent=true){
		var results = {};
		// criteria queries
		var c = newCriteria();
		// stub out activeContent alias based on potential conditions...
		// this way, we don't have to worry about accidentally creating it twice, or not creating it at all
		if(
			( structKeyExists(arguments,"author") AND arguments.author NEQ "all" ) ||
			( len(arguments.search) ) ||
			( findNoCase( "modifiedDate", arguments.sortOrder ) )
		) {
			c.createAlias( "activeContent", "ac" );
		}
		// create sort order for aliased property
		if( findNoCase( "modifiedDate", arguments.sortOrder ) ) {
			sortOrder = replaceNoCase( arguments.sortOrder, "modifiedDate", "ac.createdDate" );
		}
		// isPublished filter
		if( structKeyExists(arguments,"isPublished") AND arguments.isPublished NEQ "any"){
			c.eq("isPublished", javaCast("boolean",arguments.isPublished));
		}
		// Author Filter
		if( structKeyExists(arguments,"author") AND arguments.author NEQ "all"){
			c.isEq("ac.author.authorID", javaCast("int",arguments.author) );
		}
		// Search Criteria	
		if( len(arguments.search) ){
			// Search with active content
			if( arguments.searchActiveContent ){
				// like disjunctions
				c.or( c.restrictions.like("title","%#arguments.search#%"),
					  c.restrictions.like("ac.content", "%#arguments.search#%") );
			}
			else{
				c.like("title","%#arguments.search#%");
			}
		}
		// parent filter
		if( structKeyExists(arguments,"parent") ){
			if( len( trim(arguments.parent) ) ){
				c.eq("parent.contentID", javaCast("int",arguments.parent) );
			}
			else{
				c.isNull("parent");
			}
			sortOrder = "order asc";
		}
		// Category Filter
		if( structKeyExists(arguments,"category") AND arguments.category NEQ "all"){
			// Uncategorized?
			if( arguments.category eq "none" ){
				c.isEmpty("categories");
			}
			// With categories
			else{
				// search the association
				c.createAlias("categories","cats")
					.isIn("cats.categoryID", JavaCast("java.lang.Integer[]",[arguments.category]) );
			}
		}
		
		// run criteria query and projections count
		results.count 	= c.count("contentID");
		results.pages 	= c.resultTransformer( c.DISTINCT_ROOT_ENTITY )
							.list(offset=arguments.offset, max=arguments.max, sortOrder=sortOrder, asQuery=false);
		return results;
	}

	/**
	* Find published pages in ContentBox that have no passwords
	* @max.hint The max number of pages to return, defaults to 0=all
	* @offset.hint The pagination offset
	* @searchTerm.hint Pass a search term to narrow down results
	* @category.hint Pass a list of categories to narrow down results
	* @asQuery.hint Return results as array of objects or query, default is array of objects
	* @parent.hint The parent ID to restrict the search on
	* @showInMenu.hint If passed, it limits the search to this content property
	* @sortOrder.hint The sort order string, defaults to publisedDate DESC
	*/
	function findPublishedPages(
		numeric max=0,
		numeric offset=0,
		string searchTerm="",
		string category="",
		boolean asQuery=false,
		string parent,
		boolean showInMenu,
		string sortOrder="publishedDate DESC"
	){
		var results = {};
		var c = newCriteria();

		// only published pages
		c.isTrue( "isPublished" )
			.isLT( "publishedDate", Now() )
			.$or( c.restrictions.isNull( "expireDate" ), c.restrictions.isGT( "expireDate", now() ) )
			// only non-password pages
			.isEq( "passwordProtection", "" );

		// Show only pages with showInMenu criteria?
		if( structKeyExists( arguments, "showInMenu" ) ){
			c.isEq( "showInMenu", javaCast( "boolean", arguments.showInMenu ) );
		}

		// Category Filter
		if( len( arguments.category ) ){
			// create association with categories by slug.
			c.createAlias( "categories", "cats" ).isIn( "cats.slug", listToArray( arguments.category ) );
		}

		// Search Criteria
		if( len(arguments.searchTerm) ){
			// like disjunctions
			c.createAlias( "activeContent", "ac" );
			c.or( c.restrictions.like( "title", "%#arguments.searchTerm#%" ),
				  c.restrictions.like( "ac.content", "%#arguments.searchTerm#%" ) );
		}

		// parent filter
		if( structKeyExists(arguments,"parent") ){
			if( len( trim( arguments.parent ) ) ){
				c.eq( "parent.contentID", javaCast( "int", arguments.parent ) );
			} else {
				c.isNull( "parent" );
			}
			// change sort by parent
			arguments.sortOrder = "order asc";
		}

		// run criteria query and projections count
		results.count 	= c.count("contentID");
		results.pages 	= c.resultTransformer( c.DISTINCT_ROOT_ENTITY )
							.list( offset=arguments.offset,
								   max=arguments.max,
								   sortOrder=arguments.sortOrder,
								   asQuery=arguments.asQuery);

		return results;
	}
	
	/**
	* Returns an array of [contentID, title, slug] structures of all the pages in the system
	*/
	array function getAllFlatPages(){
		var c = newCriteria();
		
		return c.withProjections(property="contentID,title,slug")
			.resultTransformer( c.ALIAS_TO_ENTITY_MAP )
			.list(sortOrder="title asc");
			 
	}
	
	/**
	* Get all content for export as flat data
	*/
	array function getAllForExport(){
		return super.getAllForExport( newCriteria().isNull( "parent" ).list() );
	}

}