-- Script V8 : Export Photos/Videos avec ID stable, rollback et rapport complet
-- Photos -> JPG (qualite 80), videos -> copie format exporte
-- Live Photos -> les deux composants (JPG + MOV) sont exportes
-- Nouvelle extension inconnue -> export annule et rollback complet des fichiers crees
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

on isPhotoExtension(extValue)
	set photoExts to {"jpg", "jpeg", "heic", "heif", "png", "tiff", "tif", "bmp", "gif", "webp", "raw", "cr2", "nef", "arw", "dng"}
	return (photoExts contains extValue)
end isPhotoExtension

on isMediaExtension(extValue)
	return (my isPhotoExtension(extValue)) or (my isVideoExtension(extValue))
end isMediaExtension

on isSidecarExtension(extValue)
	set sidecarExts to {"aae", "xmp", "json", "plist", "xml", "thm", "dop", "ds_store"}
	return (sidecarExts contains extValue)
end isSidecarExtension

on fileNameFromPath(filePath)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set fileName to last text item of filePath
	set AppleScript's text item delimiters to oldDelims
	return fileName
end fileNameFromPath

on linesFromText(rawText)
	if rawText is "" then return {}
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set outLines to text items of rawText
	set AppleScript's text item delimiters to oldDelims
	return outLines
end linesFromText

on atomicCopyFile(srcPath, destPath, finalStem, targetExt)
	return do shell script "f=" & quoted form of (destPath & finalStem) & "; e=" & quoted form of targetExt & "; s=" & quoted form of srcPath & "; p=\"$f.$e\"; c=1; while true; do if [ -e \"$p\" ]; then p=\"${f}_${c}.${e}\"; c=$((c+1)); if [ $c -gt 999 ]; then echo FAIL; exit 1; fi; continue; fi; if cp -n \"$s\" \"$p\" 2>/dev/null && [ -f \"$p\" ]; then echo \"$p\"; exit 0; fi; p=\"${f}_${c}.${e}\"; c=$((c+1)); if [ $c -gt 999 ]; then echo FAIL; exit 1; fi; done"
end atomicCopyFile

on atomicSipsConvert(srcPath, destPath, finalStem, targetExt)
	return do shell script "f=" & quoted form of (destPath & finalStem) & "; e=" & quoted form of targetExt & "; s=" & quoted form of srcPath & "; d=" & quoted form of destPath & "; tmp=$(mktemp \"${d}.tmp.XXXXXX\"); sips -s format jpeg -s formatOptions 80 \"$s\" --out \"$tmp\" >/dev/null 2>&1 || { rm -f \"$tmp\"; echo FAIL; exit 1; }; p=\"$f.$e\"; c=1; while true; do if [ -e \"$p\" ]; then p=\"${f}_${c}.${e}\"; c=$((c+1)); if [ $c -gt 999 ]; then rm -f \"$tmp\"; echo FAIL; exit 1; fi; continue; fi; if mv -n \"$tmp\" \"$p\" 2>/dev/null && [ ! -f \"$tmp\" ]; then echo \"$p\"; exit 0; fi; p=\"${f}_${c}.${e}\"; c=$((c+1)); if [ $c -gt 999 ]; then rm -f \"$tmp\"; echo FAIL; exit 1; fi; done"
end atomicSipsConvert

on rollbackCreatedFiles(pathList)
	set deletedCount to 0
	repeat with p in pathList
		try
			set filePath to contents of p
			set fileExists to do shell script "[ -f " & quoted form of filePath & " ] && echo yes || echo no"
			if fileExists is "yes" then
				do shell script "rm -f " & quoted form of filePath
				set deletedCount to deletedCount + 1
			end if
		end try
	end repeat
	return deletedCount
end rollbackCreatedFiles

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
	
	set totalItems to count of mediaItems
	set deliveredItemCount to 0
	set deliveredFileCount to 0
	set primaryFileCount to 0
	set fallbackFileCount to 0
	set jpgConversionFailureCount to 0
	set jpgFallbackFileCount to 0
	set skippedItemCount to 0
	set failedCount to 0
	set runLog to ""
	set createdOutputPaths to {}
	
	set abortRun to false
	set abortExtension to ""
	set abortFilePath to ""
	set rollbackDeletedCount to 0
	
	display notification "Export de " & totalItems & " elements..." with title "Export avec ID"
	
	repeat with i from 1 to totalItems
		set theItem to item i of mediaItems
		set itemTempPath to ""
		set itemDelivered to false
		
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
			
			-- 3) Recuperer tous les fichiers exportes
			set exportedRaw to do shell script "find " & quoted form of itemTempPath & " -maxdepth 1 -type f | LC_ALL=C sort || true"
			set exportedPaths to my linesFromText(exportedRaw)
			
			if (count of exportedPaths) is 0 then
				set runLog to my appendLog(runLog, "SKIP item " & i & " : export introuvable")
			else
				repeat with exportedFile in exportedPaths
					set inputFilePath to contents of exportedFile
					set inputFileName to my fileNameFromPath(inputFilePath)
					set inputExt to my extensionFromPath(inputFilePath)

					if inputFileName starts with "._" then
						set runLog to my appendLog(runLog, "SKIP-FILE item " & i & " : resource fork " & inputFilePath)
					else if my isMediaExtension(inputExt) then
						set inputIsVideo to my isVideoExtension(inputExt)
						
						if inputIsVideo then
							if inputExt is "" then
								set targetExt to "mov"
							else
								set targetExt to inputExt
							end if
							
							try
								set outputFilePath to my atomicCopyFile(inputFilePath, destPath, finalStem, targetExt)
								if outputFilePath is "FAIL" then error "atomic copy failed" number -8100
								set primaryFileCount to primaryFileCount + 1
								set deliveredFileCount to deliveredFileCount + 1
								set itemDelivered to true
								set end of createdOutputPaths to outputFilePath
								set runLog to my appendLog(runLog, "OK item " & i & " : " & outputFilePath)
							on error copyErrMsg number copyErrNum
								set fallbackExt to inputExt
								if fallbackExt is "" then set fallbackExt to "bin"
								try
									set fallbackPath to my atomicCopyFile(inputFilePath, destPath, finalStem & "-orig", fallbackExt)
									if fallbackPath is "FAIL" then error "atomic fallback failed" number -8200
									set fallbackFileCount to fallbackFileCount + 1
									set deliveredFileCount to deliveredFileCount + 1
									set itemDelivered to true
									set end of createdOutputPaths to fallbackPath
									set runLog to my appendLog(runLog, "FALLBACK item " & i & " : " & fallbackPath & " (erreur copy " & copyErrNum & ")")
								on error fallbackErrMsg number fallbackErrNum
									set failedCount to failedCount + 1
									set runLog to my appendLog(runLog, "FAIL item " & i & " : copy=" & copyErrNum & ", fallback=" & fallbackErrNum)
								end try
							end try
						else
							set targetExt to "jpg"
							try
								set outputFilePath to my atomicSipsConvert(inputFilePath, destPath, finalStem, targetExt)
								if outputFilePath is "FAIL" then error "atomic convert failed" number -8300
								set primaryFileCount to primaryFileCount + 1
								set deliveredFileCount to deliveredFileCount + 1
								set itemDelivered to true
								set end of createdOutputPaths to outputFilePath
								set runLog to my appendLog(runLog, "OK item " & i & " : " & outputFilePath)
							on error convertErrMsg number convertErrNum
								set jpgConversionFailureCount to jpgConversionFailureCount + 1
								set fallbackExt to inputExt
								if fallbackExt is "" then set fallbackExt to "bin"
								try
									set fallbackPath to my atomicCopyFile(inputFilePath, destPath, finalStem & "-orig", fallbackExt)
									if fallbackPath is "FAIL" then error "atomic fallback failed" number -8400
									set fallbackFileCount to fallbackFileCount + 1
									set jpgFallbackFileCount to jpgFallbackFileCount + 1
									set deliveredFileCount to deliveredFileCount + 1
									set itemDelivered to true
									set end of createdOutputPaths to fallbackPath
									set runLog to my appendLog(runLog, "FALLBACK item " & i & " : " & fallbackPath & " (erreur JPG " & convertErrNum & ")")
								on error fallbackErrMsg number fallbackErrNum
									set failedCount to failedCount + 1
									set runLog to my appendLog(runLog, "FAIL item " & i & " : convert=" & convertErrNum & ", fallback=" & fallbackErrNum)
								end try
							end try
						end if
						
					else if my isSidecarExtension(inputExt) then
						set runLog to my appendLog(runLog, "SKIP-FILE item " & i & " : sidecar " & inputFilePath)
					else
						set abortRun to true
						set abortExtension to inputExt
						if abortExtension is "" then set abortExtension to "(no extension)"
						set abortFilePath to inputFilePath
						error "UNKNOWN_EXTENSION" number -7001
					end if
				end repeat
			end if
			
		on error itemErrMsg number itemErrNum
			if itemErrNum is -7001 then
				set runLog to my appendLog(runLog, "ABORT item " & i & " : nouvelle extension detectee (" & abortExtension & ") -> rollback")
			else
				set failedCount to failedCount + 1
				set runLog to my appendLog(runLog, "FAIL item " & i & " : " & itemErrNum & " (" & itemErrMsg & ")")
			end if
		end try
		
		if itemDelivered then
			set deliveredItemCount to deliveredItemCount + 1
		else if not abortRun then
			set skippedItemCount to skippedItemCount + 1
		end if
		
		-- Nettoyage temp item, meme en cas d'erreur
		if itemTempPath is not "" then
			try
				do shell script "rm -rf " & quoted form of itemTempPath
			end try
		end if
		
		if abortRun then exit repeat
		
		-- Progression
		if i mod 10 is 0 then
			display notification "Exporte " & i & " / " & totalItems & "..." with title "Export avec ID"
		end if
	end repeat
	
	-- Nettoyage temp run final
	try
		do shell script "rm -rf " & quoted form of tempRootPath
	end try
	
	-- Si extension inconnue, rollback complet des fichiers crees
	if abortRun then
		set rollbackDeletedCount to my rollbackCreatedFiles(createdOutputPaths)
		set summaryText to "Nouvelle extension detectee (" & abortExtension & "). Export reverti. Merci de mettre a jour le script." & return & "Fichier: " & abortFilePath & return & "Fichiers de ce run supprimes: " & rollbackDeletedCount & return & "(Un rapport de diagnostic est conserve dans le dossier d'export.)"
	else
		if deliveredItemCount is totalItems then
			set summaryLead to "Tous les items ont ete livres (" & totalItems & ")."
		else
			set summaryLead to "Items livres: " & deliveredItemCount & " / " & totalItems
		end if
		set summaryText to summaryLead & return & "Fichiers exportes: " & deliveredFileCount & " (standard: " & primaryFileCount & ", fallback: " & fallbackFileCount & ")" & return & "Conversions JPG impossibles: " & jpgConversionFailureCount & " ; sauvegardees en originaux: " & jpgFallbackFileCount & return & "Items ignores: " & skippedItemCount & return & "Erreurs: " & failedCount
	end if
	
	-- Rapport persistant + resume
	set reportPath to destPath & "export-report-" & runToken & ".txt"
	
	try
		set reportRef to open for access (POSIX file reportPath) with write permission
		set eof reportRef to 0
		write ("Export report" & return & "Run: " & runToken & return & "Total selection: " & totalItems & return & "Items livres: " & deliveredItemCount & return & "Fichiers exportes: " & deliveredFileCount & return & "Fichiers standard: " & primaryFileCount & return & "Fichiers fallback: " & fallbackFileCount & return & "Conversions JPG impossibles: " & jpgConversionFailureCount & return & "Conversions JPG sauvees en originaux: " & jpgFallbackFileCount & return & "Items ignores: " & skippedItemCount & return & "Erreurs: " & failedCount & return & "Abort run: " & abortRun & return & "Extension inconnue: " & abortExtension & return & "Fichier extension inconnue: " & abortFilePath & return & "Rollback fichiers supprimes: " & rollbackDeletedCount & return & return & runLog) to reportRef
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
