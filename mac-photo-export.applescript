-- Script V7 : Export Photos/Videos avec ID stable et rapport
-- Photos -> JPG (qualite 80), videos -> copie format exporte
-- Live Photos -> les deux composants (JPG + MOV) sont exportes
-- Sidecars (.aae etc.) filtres, ecritures atomiques, compteurs item/fichier
-- Nom : YYMMDD-HHMM-SS-<ID8>.<ext>

on twoDigits(n)
	return text -2 thru -1 of ("0" & (n as string))
end twoDigits

on lowerText(inputText)
	set sourceChars to "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	set targetChars to "abcdefghijklmnopqrstuvwxyz"
	set lowered to ""
	repeat with i from 1 to (length of inputText)
		set currentChar to character i of inputText
		set p to offset of currentChar in sourceChars
		if p is 0 then
			set lowered to lowered & currentChar
		else
			set lowered to lowered & character p of targetChars
		end if
	end repeat
	return lowered
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

on isMediaExtension(extValue)
	set photoExts to {"jpg", "jpeg", "heic", "heif", "png", "tiff", "tif", "bmp", "gif", "webp", "raw", "cr2", "nef", "arw", "dng"}
	set videoExts to {"mov", "mp4", "m4v", "avi", "mkv", "3gp", "mts", "m2ts", "wmv", "webm"}
	return (photoExts contains extValue) or (videoExts contains extValue)
end isMediaExtension

on linesFromText(rawText)
	if rawText is "" then return {}
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set outLines to text items of rawText
	set AppleScript's text item delimiters to oldDelims
	return outLines
end linesFromText

on atomicCopyFile(srcPath, destPath, finalStem, targetExt)
	return do shell script "f=" & quoted form of (destPath & finalStem) & "; e=" & quoted form of targetExt & "; s=" & quoted form of srcPath & "; p=\"$f.$e\"; c=1; while true; do if cp -n \"$s\" \"$p\" 2>/dev/null && [ -f \"$p\" ]; then echo \"$p\"; exit 0; fi; p=\"${f}_${c}.${e}\"; c=$((c+1)); if [ $c -gt 999 ]; then echo FAIL; exit 1; fi; done"
end atomicCopyFile

on atomicSipsConvert(srcPath, destPath, finalStem, targetExt)
	return do shell script "f=" & quoted form of (destPath & finalStem) & "; e=" & quoted form of targetExt & "; s=" & quoted form of srcPath & "; d=" & quoted form of destPath & "; tmp=$(mktemp \"${d}.tmp.XXXXXX\"); sips -s format jpeg -s formatOptions 80 \"$s\" --out \"$tmp\" >/dev/null 2>&1 || { rm -f \"$tmp\"; echo FAIL; exit 1; }; p=\"$f.$e\"; c=1; while true; do if mv -n \"$tmp\" \"$p\" 2>/dev/null && [ ! -f \"$tmp\" ]; then echo \"$p\"; exit 0; fi; p=\"${f}_${c}.${e}\"; c=$((c+1)); if [ $c -gt 999 ]; then rm -f \"$tmp\"; echo FAIL; exit 1; fi; done"
end atomicSipsConvert

on appendLog(currentLog, lineText)
	if currentLog is "" then return lineText
	return currentLog & return & lineText
end appendLog

tell application "Photos"
	activate
	
	set mediaItems to selection
	if mediaItems is {} then
		display dialog "Selectionnez d'abord des photos ou videos." buttons {"OK"} default button 1 with icon caution
		return
	end if
	
	set destFolder to choose folder with prompt "Dossier d'export :"
	set destPath to POSIX path of destFolder
	
	set runToken to do shell script "uuidgen | tr '[:upper:]' '[:lower:]'"
	set tempRootPath to (POSIX path of (path to temporary items)) & "mac-photo-export-" & runToken & "/"
	do shell script "mkdir -p " & quoted form of tempRootPath
	
	set itemSuccessCount to 0
	set fileCount to 0
	set fallbackCount to 0
	set skippedCount to 0
	set failedCount to 0
	set runLog to ""
	
	set totalItems to count of mediaItems
	display notification "Export de " & totalItems & " elements..." with title "Export avec ID"

	repeat with i from 1 to totalItems
		set theItem to item i of mediaItems
		set itemTempPath to ""
		set itemOK to false

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
			
			-- 3) Recuperer les fichiers media exportes (filtre les .aae et autres sidecars)
			-- Note: les noms de fichiers exportes par Photos.app ne contiennent pas de retours a la ligne
			set exportedRaw to do shell script "find " & quoted form of itemTempPath & " -maxdepth 1 -type f | grep -iE '\\.(jpg|jpeg|heic|heif|png|tiff|tif|bmp|gif|webp|raw|cr2|nef|arw|dng|mov|mp4|m4v|avi|mkv|3gp|mts|m2ts|wmv|webm)$' | LC_ALL=C sort || true"
			set exportedPaths to my linesFromText(exportedRaw)

			if (count of exportedPaths) is 0 then
				set skippedCount to skippedCount + 1
				set runLog to my appendLog(runLog, "SKIP item " & i & " : export introuvable")
			else
				-- 4) Traiter chaque fichier exporte (photo et/ou video)
				repeat with exportedFile in exportedPaths
					set inputFilePath to contents of exportedFile
					set inputExt to my extensionFromPath(inputFilePath)

					-- Defense en profondeur : ignorer les fichiers non-media
					if not my isMediaExtension(inputExt) then
						set runLog to my appendLog(runLog, "SKIP-FILE item " & i & " : non-media " & inputFilePath)
					else
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

						try
							if inputIsVideo then
								set outputFilePath to my atomicCopyFile(inputFilePath, destPath, finalStem, targetExt)
							else
								set outputFilePath to my atomicSipsConvert(inputFilePath, destPath, finalStem, targetExt)
							end if
							if outputFilePath is "FAIL" then error "atomic write failed" number -1
							set fileCount to fileCount + 1
							set itemOK to true
							set runLog to my appendLog(runLog, "OK item " & i & " : " & outputFilePath)
						on error convertErrMsg number convertErrNum
							-- Fallback : garder une copie originale exportee pour ne pas perdre l'item
							set fallbackExt to inputExt
							if fallbackExt is "" then set fallbackExt to "bin"
							try
								set fallbackPath to my atomicCopyFile(inputFilePath, destPath, finalStem & "-orig", fallbackExt)
								if fallbackPath is "FAIL" then error "atomic fallback failed" number -2
								set fallbackCount to fallbackCount + 1
								set runLog to my appendLog(runLog, "FALLBACK item " & i & " : " & fallbackPath & " (erreur " & convertErrNum & ")")
							on error fallbackErrMsg number fallbackErrNum
								set failedCount to failedCount + 1
								set runLog to my appendLog(runLog, "FAIL item " & i & " : conversion=" & convertErrNum & ", fallback=" & fallbackErrNum)
							end try
						end try
					end if
				end repeat
				if itemOK then set itemSuccessCount to itemSuccessCount + 1
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
	set summaryText to "Export termine." & return & "Items: " & itemSuccessCount & " OK / " & totalItems & " total" & return & "Fichiers: " & fileCount & " exportes" & return & "Fallback: " & fallbackCount & return & "Ignores: " & skippedCount & return & "Echecs: " & failedCount
	set reportPath to destPath & "export-report-" & runToken & ".txt"
	
	try
		set reportRef to open for access (POSIX file reportPath) with write permission
		set eof reportRef to 0
		write ("Export report" & return & "Run: " & runToken & return & "Total selection: " & totalItems & return & "Items OK: " & itemSuccessCount & return & "Fichiers exportes: " & fileCount & return & "Fallback: " & fallbackCount & return & "Ignores: " & skippedCount & return & "Echecs: " & failedCount & return & return & runLog) to reportRef
		close access reportRef
		set summaryText to summaryText & return & "Rapport: " & reportPath
	on error reportErrMsg
		try
			close access reportRef
		end try
		set summaryText to summaryText & return & "Erreur ecriture rapport: " & reportErrMsg
	end try
	
	display dialog summaryText buttons {"Parfait"} default button 1 with icon note
end tell
