-- Kindle Create Batch Automation
-- Automates: Set Virtual Panel, R2L, Facing Pages → Import images → Export KPF
--
-- Usage: osascript kindle-create-batch.applescript <images_dir> <output_dir>
--   images_dir: parent folder containing subfolders (one per volume) of numbered images
--   output_dir: where KPF files will be saved
--
-- Prerequisites: Kindle Create must be open on the "New Comic" screen.
-- Grant Accessibility permissions to your terminal app in
--   System Settings → Privacy & Security → Accessibility

on run argv
	if (count of argv) < 2 then
		error "Usage: osascript kindle-create-batch.applescript <images_dir> <output_dir>"
	end if

	set imagesParentDir to item 1 of argv
	set outputDir to item 2 of argv

	-- Get list of volume folders
	set volumeFolders to do shell script "ls -d " & quoted form of imagesParentDir & "/*/ | sort"
	set volumeList to paragraphs of volumeFolders

	set totalVolumes to count of volumeList
	set currentVolume to 0

	repeat with volPath in volumeList
		set currentVolume to currentVolume + 1
		set volName to do shell script "basename " & quoted form of volPath

		log "=== [" & currentVolume & "/" & totalVolumes & "] Processing: " & volName & " ==="

		-- Check if KPF already exists (skip if so)
		set kpfPath to outputDir & "/" & volName & ".kpf"
		try
			do shell script "test -f " & quoted form of kpfPath
			log "  SKIP: KPF already exists"
		on error
			my processVolume(volPath, volName, outputDir)
		end try
	end repeat

	log "=== All done! ==="
end run

on processVolume(imagesDir, volumeName, outputDir)
	tell application "Kindle Create" to activate
	delay 2

	tell application "System Events"
		tell process "Kindle Create"
			set frontmost to true
			delay 1

			-- Set options on the new project screen
			-- Virtual Panel
			try
				click radio button "Virtual Panel" of window 1
			end try
			delay 0.3

			-- Right-to-Left
			try
				click radio button "Right-to-Left" of window 1
			end try
			delay 0.3

			-- Facing Pages
			try
				click radio button "Facing Pages" of window 1
			end try
			delay 0.3

			-- Find and click the Choose Files button (last button area)
			-- Look for any button that might be the import button
			set allButtons to every button of window 1
			set foundChoose to false
			repeat with btn in allButtons
				try
					set btnName to name of btn
					if btnName contains "Choose" or btnName contains "Import" or btnName contains "Open" then
						click btn
						set foundChoose to true
						exit repeat
					end if
				end try
			end repeat

			-- If no named button found, look for buttons by position (bottom right area)
			if not foundChoose then
				-- Try the last few buttons
				set btnCount to count of allButtons
				if btnCount > 0 then
					-- The choose files button is typically at the bottom
					repeat with i from btnCount to (btnCount - 3) by -1
						try
							set btn to item i of allButtons
							set btnPos to position of btn
							-- Click if it's in the lower portion of window
							click btn
							set foundChoose to true
							exit repeat
						end try
					end repeat
				end if
			end if

			delay 2

			-- File dialog should be open
			-- Use Go To Folder
			keystroke "g" using {command down, shift down}
			delay 1.5

			-- Type the path to images folder
			keystroke imagesDir
			delay 0.5
			keystroke return
			delay 2

			-- Select all files
			keystroke "a" using command down
			delay 0.5

			-- Click Open/Choose
			keystroke return
			delay 3

			-- Wait for import to complete
			-- Kindle Create shows a progress indicator during import
			log "  Waiting for import..."
			set maxWait to 300
			set waited to 0
			repeat while waited < maxWait
				delay 5
				set waited to waited + 5
				try
					-- Check if Export menu item exists and is enabled
					set menuExists to exists menu item "Export as KPF" of menu "File" of menu bar 1
					if menuExists then
						exit repeat
					end if
				on error
					-- Still importing or menu not available
				end try
			end repeat

			log "  Import complete. Exporting KPF..."
			delay 2

			-- Export as KPF
			click menu item "Export as KPF" of menu "File" of menu bar 1
			delay 3

			-- Save dialog
			-- Go to output directory
			keystroke "g" using {command down, shift down}
			delay 1.5
			keystroke outputDir
			delay 0.5
			keystroke return
			delay 2

			-- Set filename
			keystroke "a" using command down
			delay 0.2
			keystroke volumeName
			delay 0.5

			-- Save
			keystroke return
			delay 3

			-- Wait for export to finish
			log "  Waiting for export..."
			set maxWait to 600
			set waited to 0
			repeat while waited < maxWait
				delay 5
				set waited to waited + 5
				try
					do shell script "test -f " & quoted form of (outputDir & "/" & volumeName & ".kpf")
					set size1 to do shell script "stat -f %z " & quoted form of (outputDir & "/" & volumeName & ".kpf")
					delay 3
					set size2 to do shell script "stat -f %z " & quoted form of (outputDir & "/" & volumeName & ".kpf")
					if size1 = size2 then
						log "  Export complete."
						exit repeat
					end if
				on error
					-- File doesn't exist yet
				end try
			end repeat

			delay 2

			-- Close project: File → New (to start fresh for next volume)
			-- This will prompt to save - we don't want to save the .kcb
			keystroke "n" using command down
			delay 2

			-- Handle "Don't Save" dialog
			try
				click button "Don't Save" of sheet 1 of window 1
			on error
				try
					click button "Don't Save" of window 1
				on error
					-- Try keyboard: Cmd+D for Don't Save
					keystroke "d" using command down
				end try
			end try
			delay 3

		end tell
	end tell

	log "  OK: " & volumeName & ".kpf"
end processVolume
