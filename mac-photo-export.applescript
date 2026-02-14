-- Script V3 : Export Photos vers JPG Universel
-- Format : YYMMDD-HHMM-SS.jpg
-- Force la conversion en JPG pour une compatibilité totale (Windows/Linux/Android)

tell application "Photos"
	activate
	
	set mediaItems to selection
	if mediaItems is {} then
		display dialog "Sélectionnez d'abord des photos." buttons {"OK"} default button 1 icon caution
		return
	end if
	
	set destFolder to choose folder with prompt "Dossier d'export :"
	set destPath to POSIX path of destFolder -- Chemin format Unix pour la conversion
	
	display notification "Conversion et export de " & (count of mediaItems) & " éléments..." with title "Export JPG Universel"
	
	repeat with theItem in mediaItems
		
		-- 1. CONSTRUCTION DU NOM (YYMMDD-HHMM-SS)
		set imgDate to date of theItem
		
		set y to text -2 thru -1 of ((year of imgDate) as string)
		set m to text -2 thru -1 of ("0" & (month of imgDate as integer))
		set d to text -2 thru -1 of ("0" & (day of imgDate))
		set h to text -2 thru -1 of ("0" & (hours of imgDate))
		set min to text -2 thru -1 of ("0" & (minutes of imgDate))
		set s to text -2 thru -1 of ("0" & (seconds of imgDate))
		
		set finalName to y & m & d & "-" & h & min & "-" & s
		
		-- 2. EXPORT TEMPORAIRE
		-- On exporte d'abord le fichier tel quel dans le dossier
		export {theItem} to destFolder without using originals
		
		-- 3. RECUPERATION DU FICHIER EXPORTÉ
		delay 0.5 -- Petite pause technique
		tell application "Finder"
			set exportedFiles to sort (get files of folder destFolder) by creation date
			set theExportedFile to item 1 of (reverse of exportedFiles)
			set inputFilePath to POSIX path of (theExportedFile as alias)
			set fileExt to name extension of theExportedFile
		end tell
		
		-- 4. CONVERSION FORCÉE EN JPG via TERMINAL
		-- On définit le chemin final
		set outputFilePath to destPath & finalName & ".jpg"
		
		-- Gestion des doublons (si 2 photos à la même seconde)
		set counter to 1
		tell application "Finder"
			repeat while exists (POSIX file outputFilePath as alias)
				set outputFilePath to destPath & finalName & "_" & counter & ".jpg"
				set counter to counter + 1
			end repeat
		end tell
		
		-- Commande magique : sips convertit tout en jpeg avec qualité normale (80%)
		-- Cela réduit le poids sans gâcher l'image
		try
			do shell script "sips -s format jpeg -s formatOptions 80 " & quoted form of inputFilePath & " --out " & quoted form of outputFilePath
			
			-- 5. NETTOYAGE
			-- Si le fichier d'origine n'était pas celui qu'on vient de créer, on le supprime
			if inputFilePath is not equal to outputFilePath then
				tell application "Finder"
					delete file (theExportedFile as alias)
				end tell
			end if
		on error
			-- Si erreur, on garde le fichier original mais on prévient
			display notification "Erreur sur une image"
		end try
		
	end repeat
	
	display dialog "Export terminé ! Tous vos fichiers sont des JPG universels." buttons {"Parfait"} default button 1 icon note
end tell