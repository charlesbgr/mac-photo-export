-- Script V4 : Export Photos/Videos avec ID stable
-- Photos -> JPG (qualite 80), Videos -> format exporte d'origine
-- Nom : YYMMDD-HHMM-SS-<ID8>.<ext>

on twoDigits(n)
	return text -2 thru -1 of ("0" & n)
end twoDigits

on shortTokenForText(rawValue)
	try
		set hashValue to (do shell script ("md5 -q -s " & quoted form of rawValue))
		return text 1 thru 8 of hashValue
	on error
		-- Fallback tres improbable, mais garde un suffixe stable pour le run
		return do shell script "uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8"
	end try
end shortTokenForText

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
	
	display notification "Export de " & (count of mediaItems) & " elements..." with title "Export avec ID"
	
	repeat with i from 1 to (count of mediaItems)
		set theItem to item i of mediaItems
		
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
		
		-- 2) Export isole dans un dossier temp unique (evite toute confusion dans dossier destination)
		set itemTempPath to tempRootPath & "item-" & i & "-" & shortToken & "/"
		do shell script "mkdir -p " & quoted form of itemTempPath
		set itemTempFolder to POSIX file itemTempPath as alias
		export {theItem} to itemTempFolder without using originals
		
		-- 3) Recuperer le fichier exporte de facon deterministe
		set inputFilePath to do shell script "find " & quoted form of itemTempPath & " -maxdepth 1 -type f | head -n 1"
		if inputFilePath is "" then
			display notification "Element " & i & " ignore (export introuvable)" with title "Export avec ID"
		else
			set fileExt to do shell script "basename " & quoted form of inputFilePath & " | awk -F. 'NF>1{print tolower($NF)}'"
			set videoExts to {"mov", "mp4", "m4v", "avi", "mkv", "3gp", "mts", "m2ts", "wmv"}
			set isVideo to (videoExts contains fileExt)
			
			if isVideo then
				set targetExt to fileExt
			else
				set targetExt to "jpg"
			end if
			
			-- 4) Nom final sans ecrasement (safe en dossier non vide)
			set outputFilePath to destPath & finalStem & "." & targetExt
			set counter to 1
			repeat while (do shell script "if [ -e " & quoted form of outputFilePath & " ]; then echo yes; else echo no; fi") is "yes"
				set outputFilePath to destPath & finalStem & "_" & counter & "." & targetExt
				set counter to counter + 1
			end repeat
			
			-- 5) Conversion/copie
			try
				if isVideo then
					do shell script "mv " & quoted form of inputFilePath & " " & quoted form of outputFilePath
				else
					do shell script "sips -s format jpeg -s formatOptions 80 " & quoted form of inputFilePath & " --out " & quoted form of outputFilePath
				end if
			on error errMsg number errNum
				display notification "Erreur element " & i & " (" & errNum & ")" with title "Export avec ID"
			end try
		end if
		
		-- 6) Nettoyage dossier temp item
		do shell script "rm -rf " & quoted form of itemTempPath
	end repeat
	
	-- 7) Nettoyage final
	do shell script "rm -rf " & quoted form of tempRootPath
	display dialog "Export termine. Photos en JPG, videos en format d'origine, noms avec ID." buttons {"Parfait"} default button 1 icon note
end tell
