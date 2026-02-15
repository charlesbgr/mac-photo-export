-- Script V6 : Export Photos/Videos avec ID stable et rapport
-- Photos -> JPG (qualite 80), videos -> copie format exporte
-- Live Photos -> les deux composants (JPG + MOV) sont exportes
-- Nom : YYMMDD-HHMM-SS-<ID8>.<ext>

on twoDigits(n)
	return text -2 thru -1 of ("0" & (n as string))
end twoDigits

on lowerText(inputText)
	return do shell script "echo " & quoted form of inputText & " | tr '[:upper:]' '[:lower:]'"
end lowerText

on shortTokenForText(rawValue)
	try
		set hashValue to do shell script "md5 -q -s " & quoted form of rawValue
		return text 1 thru 8 of hashValue
	on error
		return do shell script "uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8"
	end try
end shortTokenForText

on extensionFromPath(filePath)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set fileName to last text item of filePath
	set AppleScript's text item delimiters to "."
	set parts to text items of fileName
	set AppleScript's text item delimiters to oldDelims
	if (count of parts) < 2 then return ""
	return my lowerText((item -1 of parts) as string)
end extensionFromPath

on isVideoExtension(extValue)
	set videoExts to {"mov", "mp4", "m4v", "avi", "mkv", "3gp", "mts", "m2ts", "wmv", "webm"}
	return (videoExts contains extValue)
end isVideoExtension

on linesFromText(rawText)
	if rawText is "" then return {}
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set outLines to text items of rawText
	set AppleScript's text item delimiters to oldDelims
	return outLines
end linesFromText

on nextAvailablePath(destPath, finalStem, targetExt)
	return do shell script "f=" & quoted form of (destPath & finalStem) & "; e=" & quoted form of targetExt & "; p=\"$f.$e\"; c=1; while [ -e \"$p\" ]; do p=\"${f}_${c}.${e}\"; c=$((c+1)); done; echo \"$p\""
end nextAvailablePath

on appendLog(currentLog, lineText)
	if currentLog is "" then return lineText
	return currentLog & return & lineText
end appendLog

tell application "Photos"
	activate
	
	set mediaItems to selection
	if mediaItems is {} then
		display dialog "Selectionnez d'abord des photos ou videos." buttons {"OK"} default button 1 icon caution
		return
	end if
	
	set destFolder to choose folder with prompt "Dossier d'export :"
	set destPath to POSIX path of destFolder
	
	set runToken to do shell script "uuidgen | tr '[:upper:]' '[:lower:]'"
	set tempRootPath to (POSIX path of (path to temporary items)) & "mac-photo-export-" & runToken & "/"
	do shell script "mkdir -p " & quoted form of tempRootPath
	
	set successCount to 0
	set fallbackCount to 0
	set skippedCount to 0
	set failedCount to 0
	set runLog to ""
	
	set totalItems to count of mediaItems
	display notification "Export de " & totalItems & " elements..." with title "Export avec ID"

	repeat with i from 1 to totalItems
		set theItem to item i of mediaItems
		set itemTempPath to ""
		
		try
			-- 1) Nom base date + ID court stable
			set imgDate to date of theItem
			set y to text -2 thru -1 of ((year of imgDate) as string)
			set m to twoDigits(month of imgDate as integer)
			set d to twoDigits(day of imgDate)
			set h to twoDigits(hours of imgDate)
			set min to twoDigits(minutes of imgDate)
			set s to twoDigits(seconds of imgDate)
			
			try
				set mediaIdentifier to (id of theItem) as string
			on error
				set mediaIdentifier to "item-" & i
			end try
			
			set shortToken to shortTokenForText(mediaIdentifier)
			set finalStem to y & m & d & "-" & h & min & "-" & s & "-" & shortToken
			
			-- 2) Export isole dans dossier temp item
			set itemTempPath to tempRootPath & "item-" & i & "-" & shortToken & "/"
			do shell script "mkdir -p " & quoted form of itemTempPath
			set itemTempFolder to POSIX file itemTempPath as alias
			export {theItem} to itemTempFolder without using originals
			
			-- 3) Recuperer tous les fichiers exportes (Live Photos = photo + video)
			set exportedRaw to do shell script "find " & quoted form of itemTempPath & " -maxdepth 1 -type f | LC_ALL=C sort"
			set exportedPaths to my linesFromText(exportedRaw)

			if (count of exportedPaths) is 0 then
				set skippedCount to skippedCount + 1
				set runLog to my appendLog(runLog, "SKIP item " & i & " : export introuvable")
			else
				-- 4) Traiter chaque fichier exporte (photo et/ou video)
				repeat with exportedFile in exportedPaths
					set inputFilePath to contents of exportedFile
					set inputExt to my extensionFromPath(inputFilePath)
					set inputIsVideo to my isVideoExtension(inputExt)

					if inputIsVideo then
						if inputExt is "" then
							set targetExt to "mov"
						else
							set targetExt to inputExt
						end if
					else
						set targetExt to "jpg"
					end if

					set outputFilePath to my nextAvailablePath(destPath, finalStem, targetExt)

					try
						if inputIsVideo then
							do shell script "cp " & quoted form of inputFilePath & " " & quoted form of outputFilePath
							set successCount to successCount + 1
							set runLog to my appendLog(runLog, "OK item " & i & " : " & outputFilePath)
						else
							do shell script "sips -s format jpeg -s formatOptions 80 " & quoted form of inputFilePath & " --out " & quoted form of outputFilePath
							set successCount to successCount + 1
							set runLog to my appendLog(runLog, "OK item " & i & " : " & outputFilePath)
						end if
					on error convertErrMsg number convertErrNum
						-- Fallback : garder une copie originale exportee pour ne pas perdre l'item
						set fallbackExt to inputExt
						if fallbackExt is "" then set fallbackExt to "bin"
						set fallbackPath to my nextAvailablePath(destPath, finalStem & "-orig", fallbackExt)
						try
							do shell script "cp " & quoted form of inputFilePath & " " & quoted form of fallbackPath
							set fallbackCount to fallbackCount + 1
							set runLog to my appendLog(runLog, "FALLBACK item " & i & " : " & fallbackPath & " (erreur " & convertErrNum & ")")
						on error fallbackErrMsg number fallbackErrNum
							set failedCount to failedCount + 1
							set runLog to my appendLog(runLog, "FAIL item " & i & " : conversion=" & convertErrNum & ", fallback=" & fallbackErrNum)
						end try
					end try
				end repeat
			end if
			
		on error itemErrMsg number itemErrNum
			set failedCount to failedCount + 1
			set runLog to my appendLog(runLog, "FAIL item " & i & " : " & itemErrNum & " (" & itemErrMsg & ")")
		end try
		
		-- 5) Progression
		if i mod 10 is 0 then
			display notification "Exporte " & i & " / " & totalItems & "..." with title "Export avec ID"
		end if

		-- 6) Nettoyage temp item, meme en cas d'erreur
		if itemTempPath is not "" then
			try
				do shell script "rm -rf " & quoted form of itemTempPath
			end try
		end if
	end repeat
	
	-- 7) Nettoyage temp run final
	try
		do shell script "rm -rf " & quoted form of tempRootPath
	end try
	
	-- 8) Rapport persistant + resume
	set summaryText to "Export termine." & return & "Succes: " & successCount & return & "Fallback: " & fallbackCount & return & "Ignores: " & skippedCount & return & "Echecs: " & failedCount
	set reportPath to destPath & "export-report-" & runToken & ".txt"
	
	try
		set reportRef to open for access (POSIX file reportPath) with write permission
		set eof reportRef to 0
		write ("Export report" & return & "Run: " & runToken & return & "Total selection: " & (count of mediaItems) & return & "Succes: " & successCount & return & "Fallback: " & fallbackCount & return & "Ignores: " & skippedCount & return & "Echecs: " & failedCount & return & return & runLog) to reportRef
		close access reportRef
		set summaryText to summaryText & return & "Rapport: " & reportPath
	on error reportErrMsg
		try
			close access reportRef
		end try
		set summaryText to summaryText & return & "Erreur ecriture rapport: " & reportErrMsg
	end try
	
	display dialog summaryText buttons {"Parfait"} default button 1 icon note
end tell
