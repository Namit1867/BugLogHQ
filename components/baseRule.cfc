<cfcomponent displayname="baseRule" hint="This is the base component for any rule. A rule is a process that is evaluated each time a bug arrives and can determine if some actions need to be taken, such as sending an alert via email">

	<!--- the internal config structure is used to store configuration values
			for the current instance of this rule --->
	<cfset variables.config = structNew()>

	<cffunction name="init" access="public" returntype="baseRule">
		<!--- the default behavior is to copy the arguments to the config 
			but this can be overriden if other type of initialization is needed
		--->
		<cfset variables.config = duplicate(arguments)>
		<cfreturn this>
	</cffunction>
	
	<cffunction name="processRule" access="public" returnType="boolean"
				hint="This method performs the actual evaluation of the rule. Each rule is evaluated on a rawEntryBean. 
						The method returns a boolean value that can be used by the caller to determine if additional rules
						need to be evaluated.">
		<cfargument name="rawEntry" type="bugLog.components.rawEntryBean" required="true">
		<cfargument name="entry" type="bugLog.components.entry" required="true">
		<!--- this method must be implemented by rules that extend the base rule --->
		<cfreturn true>
	</cffunction>

	<cffunction name="processQueueStart" access="public" returntype="boolean" hint="This method gets called BEFORE each processing of the queue (only invoked when using the asynch listener)">
		<cfargument name="queue" type="array" required="true">
		<!--- this method must be implemented by rules that extend the base rule --->
		<cfreturn true>
	</cffunction>

	<cffunction name="processQueueEnd" access="public" returntype="boolean" hint="This method gets called AFTER each processing of the queue (only invoked when using the asynch listener)">
		<cfargument name="queue" type="array" required="true">
		<!--- this method must be implemented by rules that extend the base rule --->
		<cfreturn true>
	</cffunction>

	<cffunction name="sendToEmail" access="public" returntype="void">
		<cfargument name="rawEntryBean" type="bugLog.components.rawEntryBean" required="false">
		<cfargument name="recipient" type="string" required="true">
		<cfargument name="subject" type="string" required="false" default="BugLog: bug received">
		<cfargument name="comment" type="string" required="false" default="">
		<cfargument name="entryId" type="numeric" required="false" default="0">
		<cfargument name="includeHTMLReport" type="boolean" required="false" default="true">

		<cfscript>
			var stEntry = {};
			var buglogHref = getBaseBugLogHREF();
			var sender = getListener().getConfig().getSetting("general.adminEmail");
			var bugReportURL = "";
			var body = "";

			if(structKeyExists(arguments,"rawEntryBean")) {
				stEntry = arguments.rawEntryBean.getMemento();
			}
			 
			if(arguments.recipient eq "") {writeToCFLog("Missing 'recipient' email address. Cannot send alert email!"); return;}
		</cfscript>

		<!--- build contents of email --->
		<cfsavecontent variable="body">
			<cfoutput>
			<cfif arguments.comment neq "">
				<div style="font-family:arial;font-size:12px;">
				#arguments.comment#
				</div>
				<hr />
			</cfif>

			<cfif arguments.entryID gt 0>
				<cfset bugReportURL = getBugEntryHREF(arguments.entryID)>
				<b>Bug Report URL:</b> <a href="#bugReportURL#">#bugReportURL#</a><br />
				<hr />
			</cfif>

			<cfif structKeyExists(arguments,"rawEntryBean")>
				<table style="font-family:arial;font-size:12px;">
					<tr>
						<td><b>Message:</b></td>
						<td><strong>#stEntry.message#</strong></td>
					</tr>
					<tr>
						<td><b>Date/Time:</b></td>
						<td>#showDateTime(stEntry.receivedOn)#</td>
					</tr>
					<tr>
						<td><b>Application:</b></td>
						<td>#stEntry.applicationCode#</td>
					</tr>
					<tr>
						<td><b>Host:</b></td>
						<td>#stEntry.hostName#</td>
					</tr>
					<tr>
						<td><b>Severity:</b></td>
						<td>#stEntry.severityCode#</td>
					</tr>
					<tr>
						<td><b>Template Path:</b></td>
						<td>#stEntry.templatePath#</td>
					</tr>
					<tr valign="top">
						<td><b>Exception Message:</b></td>
						<td>#stEntry.exceptionMessage#</td>
					</tr>
					<tr valign="top">
						<td><b>Exception Detail:</b></td>
						<td>#stEntry.exceptionDetails#</td>
					</tr>
				</table>			
				
				<cfif stEntry.HTMLReport neq "" and arguments.includeHTMLReport>
					<hr />
					<b>HTML Report:</b><br />
					#stEntry.HTMLReport#
				</cfif>
				<hr />
			</cfif>