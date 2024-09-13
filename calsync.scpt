-- Set these to true to overwrite the fields with custom values, or false to sync the actual event fields
set UseCustomTitle to true -- Set to false if you want to sync the source event title
set UseCustomLocation to true -- Set to false if you want to sync the source event location
set UseCustomNotes to true -- Set to false if you want to sync the source event notes

-- Custom values to use if UseCustomTitle, UseCustomLocation, or UseCustomNotes are set to true
set customTitle to "busy"
set customLocation to "" -- Leave location empty
set customNotes to "" -- Leave notes empty

-- Custom title for private events
set privateEventTitle to "Private Event"

-- Define your calendar names (replace with your actual calendar names)
set sourceCalendars to {"Your Source Calendar Name 1", "Your Source Calendar Name 2"} -- List of source calendars
set targetCalendarName to "Your Target Calendar Name"

-- Fetch calendars by name
log "Fetching calendars..."
tell application "Calendar"
    set targetCal to calendar targetCalendarName
    set sourceCalList to {}
    
    -- Fetch each source calendar
    repeat with calName in sourceCalendars
        set end of sourceCalList to calendar calName
    end repeat

    -- Check if the target calendar was found
    if targetCal is missing value then
        display dialog "Error: Target calendar '" & targetCalendarName & "' not found."
        return
    end if

    log "Fetched target calendar successfully."
    
    -- Define the time range for fetching events (180 days in the past and 180 days in the future)
    set startDate to (current date) - (180 * days)
    set endDate to (current date) + (180 * days)

    -- Collect events from all source calendars
    set allSourceEvents to {}
    repeat with sourceCal in sourceCalList
        log "Fetching events from source calendar: " & name of sourceCal
        set sourceEvents to (every event of sourceCal whose start date is greater than startDate and start date is less than endDate)
        set allSourceEvents to allSourceEvents & sourceEvents
    end repeat

    log "Fetched " & (count of allSourceEvents) & " total events from source calendars."

    -- Fetch all events from the target calendar
    log "Fetching events from Target calendar..."
    set targetEvents to (every event of targetCal)

    log "Fetched " & (count of targetEvents) & " events from Target calendar."

    -- Sync and Update Events in Target Calendar
    log "Starting to sync events..."
    repeat with sourceEvent in allSourceEvents
        -- Get source values
        set sourceSummary to summary of sourceEvent
        set sourceStartDate to start date of sourceEvent
        set sourceEndDate to end date of sourceEvent
        set sourceLocation to location of sourceEvent
        set sourceNotes to description of sourceEvent
        set sourcePrivacy to transparency of sourceEvent -- Check if the event is marked as Private
        set eventExistsInTarget to false

        -- Apply custom title for private events, otherwise sync the title normally
        if sourcePrivacy is equal to "opaque" then -- Assuming 'opaque' indicates a private event
            set targetSummary to privateEventTitle
        else if UseCustomTitle is true then
            set targetSummary to customTitle
        else
            set targetSummary to sourceSummary
        end if

        if UseCustomLocation is true then
            set targetLocation to customLocation -- This will be empty if UseCustomLocation is true
        else
            set targetLocation to sourceLocation
        end if

        if UseCustomNotes is true then
            set targetNotes to customNotes -- This will be empty if UseCustomNotes is true
        else
            set targetNotes to sourceNotes
        end if

        -- Check if this event already exists in the target calendar (deduplication logic)
        repeat with targetEvent in targetEvents
            set targetStartDate to start date of targetEvent
            set targetEndDate to end date of targetEvent

            -- Compare start and end dates to detect existing events
            if (targetStartDate is equal to sourceStartDate) and (targetEndDate is equal to sourceEndDate) then
                set eventExistsInTarget to true
                -- If a matching event is found, update it
                log "Updating event in Target: " & targetSummary
                set summary of targetEvent to targetSummary
                set location of targetEvent to targetLocation
                set description of targetEvent to targetNotes
                set start date of targetEvent to sourceStartDate
                set end date of targetEvent to sourceEndDate
                exit repeat
            end if
        end repeat

        -- If the event doesn't exist in the target calendar, create it
        if (eventExistsInTarget is false) then
            log "Creating event in Target: " & targetSummary
            make new event at end of events of targetCal with properties {summary:targetSummary, start date:sourceStartDate, end date:sourceEndDate, location:targetLocation, description:targetNotes}
        end if
    end repeat

    -- Delete events in Target Calendar that are no longer in any Source Calendar
    log "Starting to delete events from Target that no longer exist in Source calendars..."
    repeat with targetEvent in targetEvents
        set targetStartDate to start date of targetEvent
        set targetEndDate to end date of targetEvent

        -- Check if this event exists in any of the source calendars (deduplication logic)
        set eventExistsInSource to false
        repeat with sourceEvent in allSourceEvents
            set sourceStartDate to start date of sourceEvent
            set sourceEndDate to end date of sourceEvent

            if (targetStartDate is equal to sourceStartDate) and (targetEndDate is equal to sourceEndDate) then
                set eventExistsInSource to true
                exit repeat
            end if
        end repeat

        -- If the event doesn't exist in the source calendars, delete it from the target
        if (eventExistsInSource is false) then
            log "Deleting event from Target (start: " & targetStartDate & "): " & summary of targetEvent
            delete targetEvent
        end if
    end repeat

    -- Log a success message after completion
    log "All events have been successfully synced between Source and Target calendars."
end tell
