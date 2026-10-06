<cfcomponent extends="bugLog.components.baseRule" 
			hint="This rule checks the amount of messages received on a given timespan and if the number of bugs received is greater than a given threshold, send an email alert">
	
	<cfproperty name="recipientEmail" type="string" buglogType="email" displayName="Recipient Email" hint="The email address to which to send the notifications">
	<cfproperty name="count" type="numeric" displayName="Count" hint="The number of bugreports that will trigger the rule">
	<cfproperty name="timespan" type="numeric" displayName="Timespan" hint="The number in minutes for which to count the amount of bug reports received">
	<cfproperty name="application" type="string" displayName="Application" buglogType="application" hint="The application name that will trigger the rule. Leave empty to look for all applications">
	<cfproperty name="host" type="string" displayName="Host Name" buglogType="host" hint="The host name that will trigger the rule. Leave empty to look for all hosts">
	<cfproperty name="severity" type="string" displayName="Severity Code" buglogType="severity" hint="The severity that will trigger the rule. Leave empty to look for all severities">
	<cfproperty name="sameMessage" type="boolean" displayName="Same Message?" hint="Set to True to counts only bug reports that have the same text on their message. Leave empty or False to count all messages">
	<cfproperty name="oneTimeAlertRecipient" type="string" hint="An email address to receive a one time short notification. This is sent only up to once per day.">

	<cfset ID_NOT_SET = -9999999 />
	<cfset ID_NOT_FOUND = -9999990 />

	<cffunction name="init" access="public" returntype="bugLog.components.baseRule">
		<cfargument name="recipientEmail" type="string" required="true">
		<cfargument name="count" type="numeric" required="true">
		<cfargument name="timespan" type="numeric" required="true">
		<cfargument name="application" type="string" required="false" default="">
		<cfargument name="host" type="string" required="false" default="">
		<cfargument name="severity" type="string" required="false" default="">
		<cfargument name="sameMessage" type="string" required="false" default="">
		<cfargument name="oneTimeAlertRecipient" type="string" required="false" default="">
		<cfset variables.config.recipientEmail = arguments.recipientEmail>
		<cfset variables.config.count = arguments.count>
		<cfset variables.config.timespan = arguments.timespan>
		<cfset variables.config.application = arguments.application>
		<cfset variables.config.host = arguments.host>
		<cfset variables.config.severity = arguments.severity>
		<cfset variables.config.sameMessage = arguments.sameMessage>
		<cfset variables.config.oneTimeAlertRecipient = arguments.oneTimeAlertRecipient>
		<cfset variables.lastEmailTimestamp = createDateTime(1800,1,1,0,0,0)>
		<cfset variables.lastOneTimeEmailTimestamp = createDateTime(1800,1,1,0,0,0)>
		<cfset variables.applicationID = ID_NOT_SET>
		<cfset variables.hostID = ID_NOT_SET>
		<cfset variables.severityID = ID_NOT_SET>
		<cfset variables.sameMessage = (isBoolean(variables.config.sameMessage) and variables.config.sameMessage)>
		<cfreturn this>
	</cffunction>
	
	<cffunction name="processRule" access="public" returnType="boolean">
		<cfargument name="rawEntry" type="bugLog.components.rawEntryBean" required="true">
		<cfargument name="entry" type="bugLog.components.entry" required="true">
		<cfscript>
			var qry = 0;
			var oEntryFinder = 0;
			var oEntryDAO = 0;
			var args = structNew();
			
			// only evaluate this rule if the amount of timespan minutes has passed after the last email was sent
			if( dateDiff("n", variables.lastEmailTimestamp, now()) gt variables.config.timespan ) {
			
				oEntryDAO = getDAOFactory().getDAO("entry");
				oEntryFinder = createObject("component","bugLog.components.entryFinder").init(oEntryDAO);
	
				if(variables.config.application neq "" and (variables.applicationID eq ID_NOT_SET or variables.applicationID eq ID_NOT_FOUND)) {
					variables.applicationID = getApplicationID();
				}
				if(variables.config.host neq "" and (variables.hostID eq ID_NOT_SET or variables.hostID eq ID_NOT_FOUND)) {
					variables.hostID = getHostID();
				}
				if(variables.config.severity neq "" and (variables.severityID eq ID_NOT_SET or variables.severityID eq ID_NOT_FOUND)) {
					variables.severityID = getSeverityID();
				}
				
				args = structNew();
				args.searchTerm = "";
				args.startDate = dateAdd("n", variables.config.timespan * (-1), now() );
				args.endDate = now();
				if(variables.applicationID neq ID_NOT_SET) args.applicationID = variables.applicationID;
				if(variables.hostID neq ID_NOT_SET) args.hostID = variables.hostID;
				if(variables.severityID neq ID_NOT_SET) args.severityID = variables.severityID;

				qry = oEntryFinder.search(argumentCollection = args);

				if(qry.recordCount gt 0) {
					if(variables.sameMessage) {
						qry = groupMessages(qry, variables.config.count);
						
						if(qry.recordCount gt 0) {
							logTrigger(entry);
							sendEmail(qry);
							sendAlert(qry);
						}
			
					} else if(qry.recordCount gt variables.config.count) {
						logTrigger(entry);
						sendEmail(qry);
						sendAlert(qry);
					}
				}
			
			}
			return true;
		</cfscript>
	</cffunction>

	<cffunction name="sendEmail" access="private" returntype="void" output="true">
		<cfargument name="data" type="query" required="true" hint="query with the bug report entries">
		<cfset var qryEntries = 0>
		<cfset var bugReportURL = "">
		<cfset var intro = "">
		
		<cfquery name="qryEntries" dbtype="query">
			SELECT ApplicationCode, ApplicationID, 
					HostName, HostID, 
					Message, COUNT(*) AS bugCount, MAX(createdOn) as createdOn, MAX(entryID) AS EntryID, MAX(severityCode) AS SeverityCode
				FROM arguments.data
				GROUP BY 
						ApplicationCode, ApplicationID, 
						HostName, HostID, 
						Message
				ORDER BY createdOn DESC
		</cfquery>
		
		<cfsavecontent variable="intro">
			<cfoutput>
				BugLog has received more than <strong>#variables.config.count#</strong> bug reports 
				<cfif variables.sameMessage>
					<strong>with the same message</strong>
				</cfif>
				<cfif variables.config.application neq "">
					for application <strong>#variables.config.application#</strong>
				</cfif>
				<cfif variables.config.host neq "">
					on host <strong>#variables.config.host#</strong>
				</cfif>
				<cfif variables.config.severity neq "">
					with a severity of <strong>#variables.config.severity#</strong>
				</cfif>
				on the last <strong>#variables.config.timespan#</strong> minutes.
				<br /><br />
				<cfloop query="qryEntries">
					<cfset bugReportURL = getBugEntryHREF(qryEntries.EntryID) />
					&bull; <a href="#bugReportURL#">[#qryEntries.severityCode#][#qryEntries.applicationCode#][#qryEntries.hostName#] #qryEntries.message# <cfif !variables.sameMessage>(#qryEntries.bugCount#)</cfif></a><br />
				</cfloop>
			</cfoutput>
		</cfsavecontent>

		<cfset sendToEmail(recipient = variables.config.recipientEmail,
							subject= "BugLog: bug frequency alert!", 
							comment = intro)>

		<cfset variables.lastEmailTimestamp = now()>
		
		<cfset writeToCFLog("'frequencyAlert' rule fired. Email sent.")>
	</cffunction>

	<cffunction name="getApplicationID" access="private" returntype="numeric">
		<cfset var oDAO = getDAOFactory().getDAO("application")>
		<cfset var oFinder = createObject("component","bugLog.components.appFinder").init(oDAO)>
		<cfset var o = 0>
		<cftry>
			<cfset o = oFinder.findByCode(variables.config.application)>
			<cfreturn o.getApplicationID()>
			<cfcatch type="appFinderException.ApplicationCodeNotFound">
				<cfreturn ID_NOT_FOUND>
			</cfcatch>
		</cftry>
	</cffunction>

	<cffunction name="getHostID" access="private" returntype="numeric">
		<cfset var oDAO = getDAOFactory().getDAO("host")>
		<cfset var oFinder = createObject("component","bugLog.components.hostFinder").init(oDAO)>
		<cfset var o = 0>
		<cftry>
			<cfset o = oFinder.findByName(variables.config.host)>
			<cfreturn o.getHostID()>
			<cfcatch type="hostFinderException.HostNameNotFound">
				<cfreturn ID_NOT_FOUND>
			</cfcatch>
		</cftry>
	</cffunction>

	<cffunction name="getSeverityID" access="private" returntype="numeric">
		<cfset var oDAO = getDAOFactory().getDAO("severity")>
		<cfset var oFinder = createObject("component","bugLog.components.severityFinder").init(oDAO)>
		<cfset var o = 0>
		<cftry>
			<cfset o = oFinder.findByCode(variables.config.severity)>
			<cfreturn o.getSeverityID()>
			<cfcatch type="severityFinderException.codeNotFound">
				<cfreturn ID_NOT_FOUND>
			</cfcatch>
		</cftry>
	</cffunction>

	<cffunction name="groupMessages" access="private" returntype="query">
		<cfargument name="data" type="query" required="true" hint="query with the bug report entries">
		<cfargument name="minCount" type="numeric" required="false" default="0" hint="When greater than 0, returns only messages whose count is greater than the given value">
		<cfset var qryEntries = 0>
		
		<cfquery name="qryEntries" dbtype="query">
			SELECT ApplicationCode, ApplicationID, 
					HostName, HostID, 
					SeverityCode, SeverityID,
					Message, COUNT(*) AS bugCount, MAX(createdOn) as createdOn, MAX(entryID) AS EntryID
				FROM arguments.data
				GROUP BY 
						ApplicationCode, ApplicationID, 
						HostName, HostID, 
						SeverityCode, SeverityID,
						Message
				ORDER BY createdOn DESC
		</cfquery>
		
		<cfif minCount gt 0>
			<cfquery name="qryEntries" dbtype="query">
				SELECT *
					FROM qryEntries
					WHERE bugCount > #arguments.minCount#
					ORDER BY createdOn DESC
			</cfquery>
		</cfif>
		
		<cfreturn qryEntries>
	</cffunction>

	<cffunction name="sendAlert" access="private" returntype="void" output="true">
		<cfargument name="data" type="query" required="true" hint="query with the bug report entries">
		<cfset var msg = "">
		
		<cfif variables.config.oneTimeAlertRecipient neq "" 
				and dateDiff("n", variables.lastOneTimeEmailTimestamp, now()) gt 60*24>
			
			<cfset msg = "BugLog has received more than #variables.config.count# bug reports ">
			<cfif variables.config.application neq "">
				<cfset msg = msg & "for application #variables.config.application# ">
			</cfif>
			<cfif variables.config.host neq "">
				<cfset msg = msg & "on host #variables.config.host# ">
			</cfif>
			<cfif variables.config.severity neq "">
				<cfset msg = msg & "with a severity of #variables.config.severity# ">
			</cfif>
			<cfset msg = msg & "on the last #variables.config.timespan# minutes.">
		
			<cfset sendToEmail(recipient = variables.config.oneTimeAlertRecipient,
								subject= "BugLog: Frequency alert", 
								comment = msg)>
		
			<cfset variables.lastOneTimeEmailTimestamp = now()>
			
			<cfset writeToCFLog("'frequencyAlert' rule fired. One-time alert sent.")>
		</cfif>
	</cffunction>
	
	<cffunction name="explain" access="public" returntype="string">
		<cfset var rtn = "Sends an alert ">
		<cfif variables.config.recipientEmail  neq "">
			<cfset rtn &= " to <b>#variables.config.recipientEmail#</b>">
		</cfif>
		<cfif variables.config.oneTimeAlertRecipient neq "">
			<cfset rtn &= " (and once per day to <b>#variables.config.oneTimeAlertRecipient#</b>)">
		</cfif>
		<cfset rtn &= " when receiving more than <b>#variables.config.count#</b> report<cfif variables.config.count gt 1>s</cfif>">
		<cfif variables.config.timespan  neq "">
			<cfset rtn &= " within the last <b>#variables.config.timespan#</b> minute<cfif variables.config.timespan gt 1>s</cfif>">
		</cfif>
		<cfif variables.config.application  neq "">
			<cfset rtn &= " from application <b>#variables.config.application#</b>">
		</cfif>
		<cfif variables.config.severity  neq "">
			<cfset rtn &= " with a severity of <b>#variables.config.severity#</b>">
		</cfif>
		<cfif variables.config.host  neq "">
			<cfset rtn &= " from host <b>#variables.config.host#</b>">
		</cfif>
		<cfreturn rtn>
	</cffunction>	
	
</cfcomponent>


			<div style="font-family:arial;font-size:11px;margin-top:15px;">
				** This email has been sent automatically from the BugLog server at 
				<a href="#buglogHref#">#buglogHref#</a><br />
				<em>To disable automatic notifications log into the bugLog server and disable the corresponding rule.</em>
			</div>
			</cfoutput>
		</cfsavecontent>
		
		<cfset mailerService.send(
				from = sender, 
				to = arguments.recipient,
				subject = arguments.subject,
				body = body,
				type = "html"
			) />

	</cffunction>

	<cffunction name="writeToCFLog" access="private" returntype="void" hint="writes a message to the internal cf logs">
		<cfargument name="message" type="string" required="true">
		<cflog application="true" file="bugLog_ruleProcessor" text="#arguments.message#">
		<cfif structKeyExists(variables,"listener")>
			<cfset variables.listener.logMessage(arguments.message)>
		</cfif>
	</cffunction>
	
	<cffunction name="setListener" access="public" returntype="baseRule" hint="Adds a reference to the bugLogListener instance">
		<cfargument name="listener" type="any" required="true">
		<cfset variables.listener = arguments.listener>
		<cfreturn this />
	</cffunction>

	<cffunction name="getListener" access="public" returntype="bugLog.components.bugLogListener" hint="Returns a reference to the bugLogListener instance">
		<cfreturn variables.listener />
	</cffunction>

	<cffunction name="setDAOFactory" access="public" returntype="baseRule" hint="Adds a reference to the current DAOFactory instance">
		<cfargument name="daoFactory" type="any" required="true">
		<cfset variables.daoFactory = arguments.daoFactory>
		<cfreturn this />
	</cffunction>

	<cffunction name="getDAOFactory" access="public" returntype="bugLog.components.lib.dao.DAOFactory" hint="Returns a reference to the current DAOFactory instance">
		<cfreturn variables.daoFactory />
	</cffunction>

	<cffunction name="setMailerService" access="public" returntype="baseRule" hint="Adds a reference to the mailer service">
		<cfargument name="mailerService" type="any" required="true">
		<cfset variables.mailerService = arguments.mailerService>
		<cfreturn this />
	</cffunction>

	<cffunction name="setExtensionID" access="public" returntype="baseRule" hint="Sets the ID of this extension instance">
		<cfargument name="id" type="numeric" required="true">
		<cfset variables._id_ = arguments.id>
		<cfreturn this>
	</cffunction>

	<cffunction name="getExtensionID" access="public" returntype="numeric" hint="Returns the ID of this extension instance">
		<cfreturn variables._id_ />
	</cffunction>

	<cffunction name="getBugEntryHREF" access="public" returntype="string" hint="Returns the URL to a given bug report">
		<cfargument name="entryID" type="numeric" required="true" hint="the id of the bug report">
		<cfset var utils = createObject("component","bugLog.components.util").init() />
		<cfset var href = utils.getBugEntryHREF(arguments.entryID, listener.getConfig(), listener.getInstanceName()) />
		<cfreturn href />
	</cffunction>

	<cffunction name="getBaseBugLogHREF" access="public" returntype="string" hint="Returns a web accessible URL to buglog">
		<cfset var utils = createObject("component","bugLog.components.util").init() />
		<cfset var href = utils.getBaseBugLogHREF(listener.getConfig(), listener.getInstanceName()) />
		<cfreturn href />
	</cffunction>
	
	<cffunction name="logTrigger" access="public" returntype="void" hint="logs a firing of a rule">
		<cfargument name="entry" type="bugLog.components.entry" required="true">
		<cfscript>
			var dao = getDAOFactory().getDAO("extensionLog");
			dao.save(extensionID = getExtensionID(), 
							entryID = arguments.entry.getEntryID(),
							createdOn = now());
		</cfscript>
	</cffunction>

	
	<cffunction name="getLastTrigger" access="public" returntype="query" hint="Returns a query object with information about the last time this rule was triggered">
		<cfset var qry = 0>
		<cfset var dsn = getDAOFactory().getDataProvider().getConfig().getDSN()>
		<cfquery name="qry" datasource="#dsn#">
			SELECT extensionLogID, extensionID, entryID, createdOn
				FROM extensionLog
				WHERE extensionID = <cfqueryparam cfsqltype="cf_sql_numeric" value="#getExtensionID()#">
				ORDER BY createdOn DESC
		</cfquery>
		<cfreturn qry>
	</cffunction>

	<cffunction name="explain" access="public" returntype="string" hint="returns a user friendly description of this rule">
		<cfreturn "">
	</cffunction>

	<cffunction name="showDateTime" returnType="string" access="private" hint="formats a date/time object according to user settings">
		<cfargument name="theDateTime" type="any" required="true">
		<cfset var rtn = "">
		<cfset var timezoneInfo = getListener().getConfig().getSetting("general.timezoneInfo","")>
		<cfset var dateMask = getListener().getConfig().getSetting("general.dateFormat","mm/dd/yyyy")>

		<cfif timezoneInfo neq "">
			<cfset var utils = createObject("component","bugLog.components.util").init() />
			<cfset theDateTime = utils.dateConvertZ("local2zone",theDateTime,timezoneInfo)>
		</cfif>
		<cfset rtn = dateFormat(theDateTime, dateMask) & " " & lsTimeFormat(theDateTime)>
		<cfreturn rtn>
	</cffunction>
	
</cfcomponent>
