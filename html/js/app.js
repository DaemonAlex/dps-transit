// DPS Transit NUI Application

const scheduleBoard = document.getElementById('schedule-board');
const ticketDisplay = document.getElementById('ticket-display');
const arrivalsList = document.getElementById('arrivals-list');
const stationName = document.getElementById('station-name');
const currentTime = document.getElementById('current-time');
const announcement = document.getElementById('announcement');

// Throttle settings for performance
const THROTTLE_MS = 15000;  // Minimum 15 seconds between DOM updates
const ETA_CHANGE_THRESHOLD = 30;  // Only update if ETA changes by 30+ seconds
const DISTANCE_DEADZONE = 5.0;  // Only update if train moved more than 5 meters
let lastArrivalUpdate = 0;
let pendingArrivalData = null;
let throttleTimeout = null;
let lastETAValues = {};  // Track previous ETA values
let lastTrainPositions = {};  // Track previous train positions for deadzone

// Check if ETAs have changed significantly
function hasSignificantETAChange(arrivals) {
    if (!arrivals || arrivals.length === 0) return true;

    for (const arrival of arrivals) {
        const key = arrival.trainId || arrival.destination;
        const lastETA = lastETAValues[key];
        const currentETA = arrival.eta;

        // First time seeing this train, or ETA changed significantly
        if (lastETA === undefined || Math.abs(lastETA - currentETA) >= ETA_CHANGE_THRESHOLD) {
            return true;
        }

        // Check if position changed significantly (distance deadzone)
        if (arrival.position && lastTrainPositions[key]) {
            const lastPos = lastTrainPositions[key];
            const dx = (arrival.position.x || 0) - (lastPos.x || 0);
            const dy = (arrival.position.y || 0) - (lastPos.y || 0);
            const dz = (arrival.position.z || 0) - (lastPos.z || 0);
            const distance = Math.sqrt(dx * dx + dy * dy + dz * dz);

            if (distance >= DISTANCE_DEADZONE) {
                return true;
            }
        } else if (arrival.position) {
            // First time seeing position for this train
            return true;
        }
    }

    return false;
}

// Update stored ETA values and positions
function updateStoredETAs(arrivals) {
    lastETAValues = {};
    lastTrainPositions = {};
    if (!arrivals) return;

    for (const arrival of arrivals) {
        const key = arrival.trainId || arrival.destination;
        lastETAValues[key] = arrival.eta;

        // Store position for distance deadzone
        if (arrival.position) {
            lastTrainPositions[key] = {
                x: arrival.position.x || 0,
                y: arrival.position.y || 0,
                z: arrival.position.z || 0
            };
        }
    }
}

// Throttled update function with ETA change detection
function throttledUpdateArrivals(arrivals, servicePeriod) {
    const now = Date.now();
    const timeSinceLastUpdate = now - lastArrivalUpdate;
    const hasChanges = hasSignificantETAChange(arrivals);

    // Force update if significant ETA change or enough time passed
    if (hasChanges || timeSinceLastUpdate >= THROTTLE_MS) {
        updateArrivalsDOM(arrivals, servicePeriod);
        updateStoredETAs(arrivals);
        lastArrivalUpdate = now;
        pendingArrivalData = null;

        if (throttleTimeout) {
            clearTimeout(throttleTimeout);
            throttleTimeout = null;
        }
    } else {
        // Store for later update
        pendingArrivalData = { arrivals, servicePeriod };

        // Schedule update if not already scheduled
        if (!throttleTimeout) {
            throttleTimeout = setTimeout(() => {
                if (pendingArrivalData) {
                    updateArrivalsDOM(pendingArrivalData.arrivals, pendingArrivalData.servicePeriod);
                    updateStoredETAs(pendingArrivalData.arrivals);
                    lastArrivalUpdate = Date.now();
                    pendingArrivalData = null;
                }
                throttleTimeout = null;
            }, THROTTLE_MS - timeSinceLastUpdate);
        }
    }
}

// Listen for NUI messages
window.addEventListener('message', function(event) {
    const data = event.data;

    switch(data.action) {
        case 'showSchedule':
            showScheduleBoard(data.station, data.arrivals);
            break;

        case 'hideSchedule':
            hideScheduleBoard();
            break;

        case 'updateArrivals':
            // Use throttled update for real-time tracking
            throttledUpdateArrivals(data.arrivals);
            break;

        case 'showTicket':
            showTicket(data.ticket);
            break;

        case 'hideTicket':
            hideTicket();
            break;

        case 'setAnnouncement':
            setAnnouncement(data.message);
            break;

        case 'showEmergencyAlert':
            showEmergencyAlert(data.message, data.stationName);
            break;

        case 'hideEmergencyAlert':
            hideEmergencyAlert();
            break;

        case 'showServiceAlert':
            showServiceAlert(data.alertType, data.message, data.affectedLines);
            break;

        case 'hideServiceAlert':
            hideServiceAlert();
            break;

        case 'updateDelays':
            updateDelayInfo(data.delays);
            break;

        case 'trainRemoved':
            handleTrainRemoved(data.trainId);
            break;

        case 'clearStaleTrains':
            clearStaleTrainData(data.validIds);
            break;

        // Block Signaling NUI Updates
        case 'updateTrainSegment':
            updateTrainSegment(data.trainId, data.segmentName, data.signalState);
            break;

        case 'showSignalHold':
            showSignalHold(data.segmentName, data.reason, data.isDispatcherHold);
            break;

        case 'hideSignalHold':
            hideSignalHold();
            break;

        case 'trainHeldStatus':
            updateTrainHeldStatus(data.trainId, data.isHeld, data.isCaution, data.reason, data.segmentName);
            break;

        // Passenger Announcements
        case 'showAnnouncement':
            showPassengerAnnouncement(data.type, data.title, data.station, data.subtitle, data.icon, data.duration);
            break;

        case 'hideAnnouncement':
            hidePassengerAnnouncement();
            break;

        // Dispatcher Panel
        case 'showDispatcher':
            showDispatcherPanel();
            break;

        case 'hideDispatcher':
            hideDispatcherPanel();
            break;

        case 'updateDispatcher':
            updateDispatcherData(data.segments, data.trains);
            break;

        case 'segmentOverrideChanged':
            handleSegmentOverrideChanged(data);
            break;
    }
});

// Clear train data for IDs that are no longer valid
function clearStaleTrainData(currentValidIds) {
    if (!currentValidIds || !Array.isArray(currentValidIds)) return;

    const currentSet = new Set(currentValidIds);

    // Find trains we're tracking that are no longer valid
    validTrainIds.forEach(trainId => {
        if (!currentSet.has(trainId)) {
            removeInvalidTrain(trainId);
        }
    });
}

// Show schedule board
function showScheduleBoard(station, arrivals) {
    stationName.textContent = station.toUpperCase();
    updateArrivals(arrivals);
    updateClock();
    scheduleBoard.classList.remove('hidden');

    // Start clock update
    startClockUpdate();
}

// Hide schedule board
function hideScheduleBoard() {
    scheduleBoard.classList.add('hidden');
    stopClockUpdate();
}

// Update arrivals list (called directly for initial load)
function updateArrivals(arrivals) {
    updateArrivalsDOM(arrivals);
}

// Current service state
let currentServicePeriod = 'offpeak';

// Track known valid train IDs
let validTrainIds = new Set();

// DOM update function (used by throttle)
function updateArrivalsDOM(arrivals, servicePeriod) {
    arrivalsList.innerHTML = '';

    // Mark that we've received data from server
    markDataReceived();

    // Update service period if provided
    if (servicePeriod) {
        currentServicePeriod = servicePeriod;
    }

    if (!arrivals || arrivals.length === 0) {
        showEmptyState();
        return;
    }

    // Filter out invalid/stale arrivals
    const validArrivals = arrivals.filter(arrival => {
        // Check for invalid data
        if (!arrival) return false;

        // Check for invalid ETA (negative, NaN, or extremely large)
        if (typeof arrival.eta !== 'number' || isNaN(arrival.eta) || arrival.eta < 0 || arrival.eta > 86400) {
            console.warn('Invalid ETA for arrival:', arrival);
            return false;
        }

        // Check for missing destination
        if (!arrival.destination) {
            console.warn('Missing destination for arrival:', arrival);
            return false;
        }

        // Track valid train IDs
        if (arrival.trainId) {
            validTrainIds.add(arrival.trainId);
        }

        return true;
    });

    if (validArrivals.length === 0) {
        showEmptyState();
        return;
    }

    validArrivals.forEach(arrival => {
        const row = document.createElement('div');
        row.className = 'arrival-row';
        row.dataset.trainId = arrival.trainId || '';

        // Status-aware ETA: Lock to NOW for boarding/approaching to prevent backward jump
        const status = arrival.status ? arrival.status.toLowerCase() : '';
        const isAtStation = status === 'boarding' || status === 'approaching' || status === 'departing';

        // Check for held status (from signal hold event)
        const held = heldTrainStatus[arrival.trainId];
        const isHeld = held && held.isHeld;
        const isCaution = held && held.isCaution;

        // FROZEN ETA DETECTION: If ETA hasn't changed in 30+ seconds and not at station,
        // the train is likely stopped at a signal (even if we didn't get the event)
        const lastETA = lastETAValues[arrival.trainId];
        const etaUnchanged = lastETA !== undefined && Math.abs(lastETA - arrival.eta) < 5;
        const frozenTooLong = etaUnchanged && (Date.now() - (lastDataReceiveTime || 0)) > 30000;
        const isStuckBetweenStations = frozenTooLong && !isAtStation && arrival.eta > 60;

        // Determine ETA display
        let etaDisplay;
        let etaClass = '';
        let displayStatus = arrival.status || 'On Time';

        if (isHeld || isStuckBetweenStations) {
            // Train stopped at signal - show HELD or Delayed
            if (isHeld) {
                etaDisplay = 'HELD';
                displayStatus = 'Signal Hold';
            } else {
                etaDisplay = 'DELAYED';
                displayStatus = 'Signal Hold';
            }
            etaClass = 'eta-held';
        } else if (isAtStation) {
            // Train at platform - lock to NOW to prevent backward jump
            etaDisplay = 'NOW';
            etaClass = 'arriving';
        } else if (isCaution) {
            // Train approaching under caution - show adjusted ETA
            etaDisplay = formatETA(getAdjustedETA(arrival.trainId, arrival.eta));
            etaClass = arrival.eta < 120 ? 'eta-caution' : '';
        } else {
            // Normal ETA
            etaDisplay = formatETA(arrival.eta);
            etaClass = arrival.eta < 60 ? 'arriving' : '';
        }

        const statusClass = displayStatus.toLowerCase().replace(/\s+/g, '-');

        // Add train type indicator
        const typeIcon = arrival.type === 'freight' ? '(Freight)' : '';

        row.innerHTML = `
            <div class="col-dest">${escapeHtml(arrival.destination)} ${typeIcon}</div>
            <div class="col-eta ${etaClass}">${etaDisplay}</div>
            <div class="col-status ${statusClass}">${escapeHtml(displayStatus)}</div>
        `;

        arrivalsList.appendChild(row);
    });
}

// Remove a specific train row if it becomes invalid
function removeInvalidTrain(trainId) {
    const row = document.querySelector(`.arrival-row[data-train-id="${trainId}"]`);
    if (row) {
        row.classList.add('fade-out');
        setTimeout(() => {
            row.remove();
            // Check if we need to show empty state
            if (arrivalsList.children.length === 0) {
                showEmptyState();
            }
        }, 300);
    }
    validTrainIds.delete(trainId);
    delete lastETAValues[trainId];
    delete lastTrainPositions[trainId];
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Handle train removed event
function handleTrainRemoved(trainId) {
    removeInvalidTrain(trainId);
}

// Track if we've received any data from server
let hasReceivedServerData = false;
let lastDataReceiveTime = 0;

// Show appropriate empty state message
function showEmptyState() {
    const row = document.createElement('div');
    row.className = 'arrival-row empty-state';

    let message = 'No trains scheduled';
    let subMessage = 'Check back shortly';
    let icon = 'train';

    const now = Date.now();
    const timeSinceData = now - lastDataReceiveTime;

    // Determine appropriate message based on context
    const hour = new Date().getHours();

    // If we haven't received any data yet, show "Searching..."
    if (!hasReceivedServerData) {
        message = 'Searching for Trains...';
        subMessage = 'Connecting to transit server';
        icon = 'search';
    } else if (timeSinceData > 30000) {
        // If no data received in 30+ seconds, show connection issue
        message = 'Connection Lost';
        subMessage = 'Attempting to reconnect...';
        icon = 'warning';
    } else if (currentServicePeriod === 'night' || (hour >= 22 || hour < 6)) {
        message = 'Limited Night Service';
        subMessage = 'Trains every 30 minutes';
        icon = 'moon';
    } else if (currentServicePeriod === 'starting') {
        message = 'Service Starting';
        subMessage = 'First train departing soon';
        icon = 'clock';
    } else if (currentServicePeriod === 'emergency') {
        message = 'Service Suspended';
        subMessage = 'Please follow station announcements';
        icon = 'warning';
    } else if (currentServicePeriod === 'searching') {
        message = 'Searching for Trains...';
        subMessage = 'Please wait';
        icon = 'search';
    }

    row.innerHTML = `
        <div class="empty-message">
            <div class="empty-icon">${getEmptyIcon(icon)}</div>
            <div class="empty-title">${message}</div>
            <div class="empty-subtitle">${subMessage}</div>
        </div>
    `;

    arrivalsList.appendChild(row);
}

// Mark that we've received server data
function markDataReceived() {
    hasReceivedServerData = true;
    lastDataReceiveTime = Date.now();
}

// Get icon for empty state
function getEmptyIcon(type) {
    switch(type) {
        case 'moon': return '🌙';
        case 'clock': return '⏰';
        case 'warning': return '⚠️';
        case 'search': return '🔍';
        case 'train':
        default: return '🚆';
    }
}

// Emergency alert display
function showEmergencyAlert(message, stationName) {
    const alertEl = document.getElementById('emergency-alert');
    if (alertEl) {
        alertEl.querySelector('.alert-station').textContent = stationName || 'Station';
        alertEl.querySelector('.alert-message').textContent = message || 'Service disruption';
        alertEl.classList.remove('hidden');
    }
}

function hideEmergencyAlert() {
    const alertEl = document.getElementById('emergency-alert');
    if (alertEl) {
        alertEl.classList.add('hidden');
    }
}

// Block Signaling NUI Functions
// Track current signal states for trains
const trainSignalStates = {};

// Update train segment display in arrivals list
function updateTrainSegment(trainId, segmentName, signalState) {
    trainSignalStates[trainId] = {
        segment: segmentName,
        signal: signalState,
        timestamp: Date.now()
    };

    // Find and update the arrival row for this train
    const rows = arrivalsList.querySelectorAll('.arrival-row');
    rows.forEach(row => {
        if (row.dataset.trainId === trainId) {
            // Update signal indicator
            let signalEl = row.querySelector('.signal-indicator');
            if (!signalEl) {
                signalEl = document.createElement('span');
                signalEl.className = 'signal-indicator';
                row.querySelector('.arrival-status')?.appendChild(signalEl);
            }

            // Set signal color class
            signalEl.className = 'signal-indicator signal-' + signalState;

            // Add segment tooltip
            signalEl.title = segmentName + ' - Signal: ' + signalState.toUpperCase();
        }
    });
}

// Show signal hold banner
function showSignalHold(segmentName, reason, isDispatcherHold = false) {
    // Create signal hold element if it doesn't exist
    let holdEl = document.getElementById('signal-hold');
    if (!holdEl) {
        holdEl = document.createElement('div');
        holdEl.id = 'signal-hold';
        holdEl.className = 'signal-hold-banner';
        holdEl.innerHTML = `
            <div class="signal-hold-icon">🚦</div>
            <div class="signal-hold-content">
                <div class="signal-hold-title">Signal Hold</div>
                <div class="signal-hold-segment"></div>
                <div class="signal-hold-reason"></div>
            </div>
        `;
        // Insert before arrivals list
        const board = document.getElementById('schedule-board');
        if (board) {
            board.insertBefore(holdEl, arrivalsList);
        }
    }

    // Update content and styling based on hold type
    const titleEl = holdEl.querySelector('.signal-hold-title');
    const iconEl = holdEl.querySelector('.signal-hold-icon');

    if (isDispatcherHold) {
        titleEl.textContent = 'Dispatcher Hold';
        iconEl.textContent = '🚨';
        holdEl.classList.add('dispatcher-hold');
        holdEl.classList.remove('signal-hold');
    } else {
        titleEl.textContent = 'Signal Hold';
        iconEl.textContent = '🚦';
        holdEl.classList.add('signal-hold');
        holdEl.classList.remove('dispatcher-hold');
    }

    holdEl.querySelector('.signal-hold-segment').textContent = segmentName || 'Current Section';
    holdEl.querySelector('.signal-hold-reason').textContent = reason || 'Waiting for clear signal';
    holdEl.classList.remove('hidden');
    holdEl.classList.add('signal-hold-active');
}

// Hide signal hold banner
function hideSignalHold() {
    const holdEl = document.getElementById('signal-hold');
    if (holdEl) {
        holdEl.classList.add('hidden');
        holdEl.classList.remove('signal-hold-active');
    }
}

// Get signal state class for styling
function getSignalStateClass(signalState) {
    switch(signalState) {
        case 'red': return 'signal-red';
        case 'yellow': return 'signal-yellow';
        case 'green': return 'signal-green';
        default: return '';
    }
}

// Track held train status for dynamic ETA updates
const heldTrainStatus = {};

// Update train held status (affects ETA display)
function updateTrainHeldStatus(trainId, isHeld, isCaution, reason, segmentName) {
    if (isHeld || isCaution) {
        heldTrainStatus[trainId] = {
            isHeld: isHeld,
            isCaution: isCaution,
            reason: reason || 'Signal hold',
            segmentName: segmentName,
            heldSince: heldTrainStatus[trainId]?.heldSince || Date.now()
        };
    } else {
        delete heldTrainStatus[trainId];
    }

    // Update the arrival row for this train
    const rows = arrivalsList.querySelectorAll('.arrival-row');
    rows.forEach(row => {
        if (row.dataset.trainId === trainId) {
            const etaEl = row.querySelector('.arrival-eta');
            const statusEl = row.querySelector('.arrival-status');

            if (isHeld) {
                // Show "HELD" instead of ETA
                if (etaEl) {
                    etaEl.dataset.originalEta = etaEl.textContent;
                    etaEl.textContent = 'HELD';
                    etaEl.classList.add('eta-held');
                }
                if (statusEl) {
                    statusEl.textContent = 'Signal Hold';
                    statusEl.classList.add('status-held');
                }
                row.classList.add('train-held');
            } else if (isCaution) {
                // Show "DELAYED" with caution styling
                if (etaEl) {
                    etaEl.classList.add('eta-caution');
                    etaEl.classList.remove('eta-held');
                }
                if (statusEl) {
                    statusEl.textContent = 'Caution';
                    statusEl.classList.add('status-caution');
                    statusEl.classList.remove('status-held');
                }
                row.classList.add('train-caution');
                row.classList.remove('train-held');
            } else {
                // Clear held/caution status
                if (etaEl) {
                    if (etaEl.dataset.originalEta) {
                        etaEl.textContent = etaEl.dataset.originalEta;
                        delete etaEl.dataset.originalEta;
                    }
                    etaEl.classList.remove('eta-held', 'eta-caution');
                }
                if (statusEl) {
                    statusEl.classList.remove('status-held', 'status-caution');
                }
                row.classList.remove('train-held', 'train-caution');
            }
        }
    });
}

// Get adjusted ETA considering held status
function getAdjustedETA(trainId, originalEta) {
    const held = heldTrainStatus[trainId];
    if (!held) return originalEta;

    if (held.isHeld) {
        // Train is stopped - ETA is unknown, add time since held
        const heldDuration = Math.floor((Date.now() - held.heldSince) / 1000);
        return originalEta + heldDuration;
    } else if (held.isCaution) {
        // Train is slowed to ~30% - rough estimate: add 70% to remaining time
        return Math.floor(originalEta * 1.7);
    }

    return originalEta;
}

// Format ETA for display
function formatETA(seconds) {
    if (seconds < 60) {
        return 'NOW';
    } else if (seconds < 120) {
        return '1 min';
    } else {
        return Math.floor(seconds / 60) + ' min';
    }
}

// Update clock display
function updateClock() {
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    currentTime.textContent = `${hours}:${minutes}`;
}

// Clock update interval
let clockInterval = null;

function startClockUpdate() {
    if (clockInterval) clearInterval(clockInterval);
    clockInterval = setInterval(updateClock, 1000);
}

function stopClockUpdate() {
    if (clockInterval) {
        clearInterval(clockInterval);
        clockInterval = null;
    }
}

// Show ticket
function showTicket(ticket) {
    document.getElementById('ticket-from').textContent = ticket.from;
    document.getElementById('ticket-to').textContent = ticket.to;
    document.getElementById('ticket-fare').textContent = '$' + ticket.fare;
    document.getElementById('ticket-expires').textContent = formatTime(ticket.expiresAt);
    document.getElementById('ticket-id').textContent = ticket.id;

    if (ticket.type === 'daypass') {
        document.getElementById('ticket-type').textContent = 'DAY PASS';
    } else {
        document.getElementById('ticket-type').textContent = 'SINGLE JOURNEY';
    }

    ticketDisplay.classList.remove('hidden');

    // Auto-hide after 5 seconds
    setTimeout(() => {
        hideTicket();
    }, 5000);
}

// Hide ticket
function hideTicket() {
    ticketDisplay.classList.add('hidden');
}

// Format timestamp to time string
function formatTime(timestamp) {
    const date = new Date(timestamp * 1000);
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${hours}:${minutes}`;
}

// Set announcement message
function setAnnouncement(message) {
    announcement.textContent = message;
}

// ============================================
// PASSENGER ANNOUNCEMENT OVERLAY
// ============================================

const passengerAnnouncement = document.getElementById('passenger-announcement');
const announcementIcon = document.getElementById('announcement-icon');
const announcementTitle = document.getElementById('announcement-title');
const announcementStation = document.getElementById('announcement-station');
const announcementSubtitle = document.getElementById('announcement-subtitle');

let announcementTimeout = null;
let announcementHideTimeout = null;

// Icon mapping for announcement types
const ANNOUNCEMENT_ICONS = {
    approach: '🚂',
    arrival: '🚉',
    departure: '🚃',
    held: '⚠️',
    caution: '⏳',
    default: '🚂'
};

// Show passenger announcement with animation
function showPassengerAnnouncement(type, title, station, subtitle, customIcon, duration = 5000) {
    if (!passengerAnnouncement) return;

    // Clear any existing timeouts
    if (announcementTimeout) clearTimeout(announcementTimeout);
    if (announcementHideTimeout) clearTimeout(announcementHideTimeout);

    // Remove fade-out class if present
    passengerAnnouncement.classList.remove('fade-out');

    // Set content
    announcementIcon.textContent = customIcon || ANNOUNCEMENT_ICONS[type] || ANNOUNCEMENT_ICONS.default;
    announcementTitle.textContent = title || 'Announcement';
    announcementStation.textContent = station || '';
    announcementSubtitle.textContent = subtitle || '';

    // Set type class for styling
    passengerAnnouncement.className = 'passenger-announcement';
    if (type) {
        passengerAnnouncement.classList.add('type-' + type);
    }

    // Show the announcement
    passengerAnnouncement.classList.remove('hidden');

    // Auto-hide after duration (unless it's a 'held' type which stays until cleared)
    if (type !== 'held' && duration > 0) {
        announcementTimeout = setTimeout(() => {
            hidePassengerAnnouncement();
        }, duration);
    }
}

// Hide passenger announcement with animation
function hidePassengerAnnouncement() {
    if (!passengerAnnouncement) return;

    // Clear any pending timeouts
    if (announcementTimeout) {
        clearTimeout(announcementTimeout);
        announcementTimeout = null;
    }

    // Add fade-out animation
    passengerAnnouncement.classList.add('fade-out');

    // Actually hide after animation completes
    announcementHideTimeout = setTimeout(() => {
        passengerAnnouncement.classList.add('hidden');
        passengerAnnouncement.classList.remove('fade-out');
    }, 400);  // Match CSS animation duration
}

// ============================================
// DISPATCHER CONTROL PANEL
// ============================================

const dispatcherPanel = document.getElementById('dispatcher-panel');
const dispatcherTime = document.getElementById('dispatcher-time');
const dispatcherTrainsList = document.getElementById('dispatcher-trains-list');

let dispatcherClockInterval = null;
let dispatcherUpdateInterval = null;

// Show dispatcher panel
function showDispatcherPanel() {
    if (!dispatcherPanel) return;

    // Hide schedule board if visible
    scheduleBoard.classList.add('hidden');

    dispatcherPanel.classList.remove('hidden');
    startDispatcherClock();

    // Request initial data
    fetch(`https://${GetParentResourceName()}/requestDispatcherData`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

// Hide dispatcher panel
function hideDispatcherPanel() {
    if (!dispatcherPanel) return;

    dispatcherPanel.classList.add('hidden');
    stopDispatcherClock();
}

// Update dispatcher clock (with seconds)
function updateDispatcherClock() {
    if (!dispatcherTime) return;

    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    dispatcherTime.textContent = `${hours}:${minutes}:${seconds}`;
}

function startDispatcherClock() {
    if (dispatcherClockInterval) clearInterval(dispatcherClockInterval);
    updateDispatcherClock();
    dispatcherClockInterval = setInterval(updateDispatcherClock, 1000);
}

function stopDispatcherClock() {
    if (dispatcherClockInterval) {
        clearInterval(dispatcherClockInterval);
        dispatcherClockInterval = null;
    }
}

// ============================================
// DISPATCHER SELECTION & INTERACTION STATE
// ============================================

let selectedTrainId = null;
let selectedSegmentId = null;
let currentSegmentData = {};
let currentTrainData = [];
let confirmModalVisible = false;
let pendingEmergencyTrainId = null;

// Update dispatcher data (segments and trains)
function updateDispatcherData(segments, trains) {
    if (!segments) return;

    // Store current data for tooltips and selection
    currentSegmentData = segments;
    currentTrainData = trains || [];

    // Update segment blocks
    updateSegmentBlocks(segments);

    // Update train list
    if (trains) {
        updateTrainList(trains);
    }

    // Restore selection state after update
    if (selectedTrainId) {
        highlightTrainAndSegment(selectedTrainId);
    }
}

// Update segment block visuals with tooltips
function updateSegmentBlocks(segments) {
    for (const [segmentId, data] of Object.entries(segments)) {
        const segmentEl = document.querySelector(`[data-segment="${segmentId}"]`);
        if (!segmentEl) continue;

        const blockEl = segmentEl.querySelector('.segment-block');
        if (!blockEl) continue;

        // Store segment data for click handler
        segmentEl.dataset.trainId = data.trainId || '';
        segmentEl.dataset.occupied = data.occupied ? 'true' : 'false';

        // Reset classes (preserve 'selected' if applicable)
        const isSelected = segmentEl.classList.contains('selected');
        blockEl.classList.remove('empty', 'passenger', 'freight', 'held', 'caution', 'locked');

        // Check for segment lock override (v2.6.0)
        if (data.isLocked) {
            blockEl.classList.add('locked');
        } else if (data.occupied) {
            if (data.isHeld) {
                blockEl.classList.add('held');
            } else if (data.trainType === 'freight') {
                blockEl.classList.add('freight');
            } else {
                blockEl.classList.add('passenger');
            }

            if (data.signalState === 'yellow') {
                blockEl.classList.add('caution');
            }
        } else {
            blockEl.classList.add('empty');
        }

        // Create or update tooltip
        updateSegmentTooltip(segmentEl, segmentId, data);

        // Add click handler if not already added
        if (!segmentEl.dataset.clickHandler) {
            segmentEl.dataset.clickHandler = 'true';
            segmentEl.addEventListener('click', () => handleSegmentClick(segmentId, data));
        }

        // Add context menu handler for right-click (v2.6.0)
        addSegmentContextMenuHandler(segmentEl, segmentId);
    }
}

// Create/update segment tooltip
function updateSegmentTooltip(segmentEl, segmentId, data) {
    let tooltip = segmentEl.querySelector('.segment-tooltip');

    if (!tooltip) {
        tooltip = document.createElement('div');
        tooltip.className = 'segment-tooltip';
        segmentEl.style.position = 'relative';
        segmentEl.appendChild(tooltip);
    }

    // Check for segment lock (v2.6.0)
    if (data.isLocked) {
        tooltip.innerHTML = `
            <div class="tooltip-header">${escapeHtml(data.name || segmentId)}</div>
            <div class="tooltip-row">
                <span class="tooltip-label">Status:</span>
                <span class="tooltip-value" style="color: #9b59b6;">🔒 LOCKED</span>
            </div>
            <div class="tooltip-row">
                <span class="tooltip-label">Reason:</span>
                <span class="tooltip-value">${escapeHtml(data.lockReason || 'Maintenance')}</span>
            </div>
            <div class="tooltip-row">
                <span class="tooltip-label">Locked By:</span>
                <span class="tooltip-value">${escapeHtml(data.lockedBy || 'Dispatcher')}</span>
            </div>
            <div class="tooltip-row" style="margin-top: 8px; padding-top: 8px; border-top: 1px solid #0f3460;">
                <span class="tooltip-label" style="color: #666; font-size: 10px;">Right-click to unlock</span>
            </div>
        `;
    } else if (data.occupied && data.trainId) {
        const typeClass = data.trainType === 'freight' ? 'freight' : (data.isHeld ? 'held' : 'passenger');
        const statusText = data.isHeld ? 'HELD' : (data.signalState === 'yellow' ? 'CAUTION' : 'RUNNING');
        const timeInSegment = data.timeInSegment ? formatDuration(data.timeInSegment) : '--';
        const etaClear = data.estimatedClearTime ? formatDuration(data.estimatedClearTime) : '--';

        tooltip.innerHTML = `
            <div class="tooltip-header">${escapeHtml(data.name || segmentId)}</div>
            <div class="tooltip-row">
                <span class="tooltip-label">Train:</span>
                <span class="tooltip-value ${typeClass}">${escapeHtml(data.trainId)}</span>
            </div>
            <div class="tooltip-row">
                <span class="tooltip-label">Type:</span>
                <span class="tooltip-value">${data.trainType === 'freight' ? 'Freight' : 'Passenger'}</span>
            </div>
            <div class="tooltip-row">
                <span class="tooltip-label">Status:</span>
                <span class="tooltip-value ${typeClass}">${statusText}</span>
            </div>
            <div class="tooltip-row">
                <span class="tooltip-label">In Segment:</span>
                <span class="tooltip-value">${timeInSegment}</span>
            </div>
            <div class="tooltip-row">
                <span class="tooltip-label">ETA Clear:</span>
                <span class="tooltip-value">${etaClear}</span>
            </div>
        `;
    } else {
        tooltip.innerHTML = `
            <div class="tooltip-header">${escapeHtml(data.name || segmentId)}</div>
            <div class="tooltip-row">
                <span class="tooltip-label">Status:</span>
                <span class="tooltip-value" style="color: #4ecca3;">CLEAR</span>
            </div>
            <div class="tooltip-row" style="margin-top: 8px; padding-top: 8px; border-top: 1px solid #0f3460;">
                <span class="tooltip-label" style="color: #666; font-size: 10px;">Right-click for options</span>
            </div>
        `;
    }
}

// Format duration in seconds to readable string
function formatDuration(seconds) {
    if (seconds < 60) {
        return `${Math.floor(seconds)}s`;
    } else if (seconds < 3600) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}m ${secs}s`;
    } else {
        return `${Math.floor(seconds / 3600)}h+`;
    }
}

// Handle segment click - select train
function handleSegmentClick(segmentId, data) {
    if (data.occupied && data.trainId) {
        selectTrain(data.trainId, segmentId);
    } else {
        clearSelection();
    }
}

// Select a train and highlight its segment
function selectTrain(trainId, segmentId = null) {
    // Clear previous selection
    clearSelection(false);

    selectedTrainId = trainId;

    // Find segment if not provided
    if (!segmentId) {
        for (const [sid, sdata] of Object.entries(currentSegmentData)) {
            if (sdata.trainId === trainId) {
                segmentId = sid;
                break;
            }
        }
    }

    selectedSegmentId = segmentId;

    // Highlight segment
    if (segmentId) {
        const segmentEl = document.querySelector(`[data-segment="${segmentId}"]`);
        if (segmentEl) {
            segmentEl.classList.add('selected');
        }
    }

    // Highlight train in list
    const trainItems = dispatcherTrainsList.querySelectorAll('.train-item');
    trainItems.forEach(item => {
        if (item.dataset.trainId === trainId) {
            item.classList.add('active');
        }
    });
}

// Highlight train and its segment
function highlightTrainAndSegment(trainId) {
    // Find the segment for this train
    for (const [segmentId, data] of Object.entries(currentSegmentData)) {
        if (data.trainId === trainId) {
            const segmentEl = document.querySelector(`[data-segment="${segmentId}"]`);
            if (segmentEl) {
                segmentEl.classList.add('selected');
            }
            break;
        }
    }

    // Highlight in train list
    const trainItems = dispatcherTrainsList.querySelectorAll('.train-item');
    trainItems.forEach(item => {
        if (item.dataset.trainId === trainId) {
            item.classList.add('active');
        }
    });
}

// Clear selection
function clearSelection(clearState = true) {
    // Remove segment highlight
    document.querySelectorAll('.segment.selected').forEach(el => {
        el.classList.remove('selected');
    });

    // Remove train list highlight
    document.querySelectorAll('.train-item.active').forEach(el => {
        el.classList.remove('active');
    });

    if (clearState) {
        selectedTrainId = null;
        selectedSegmentId = null;
    }
}

// Update train list with click handlers and emergency buttons
function updateTrainList(trains) {
    if (!dispatcherTrainsList) return;

    if (!trains || trains.length === 0) {
        dispatcherTrainsList.innerHTML = `
            <div class="train-item" style="justify-content: center; color: #666;">
                No active trains
            </div>
        `;
        return;
    }

    let html = '';
    for (const train of trains) {
        const typeClass = train.type === 'freight' ? 'freight' : '';
        const heldClass = train.isHeld ? 'held' : '';
        const activeClass = train.id === selectedTrainId ? 'active' : '';
        const statusClass = train.isHeld ? 'held' : (train.status === 'boarding' ? 'boarding' : 'running');

        // Emergency button state
        const btnClass = train.isHeld ? 'active' : '';
        const btnText = train.isHeld ? 'RELEASE' : 'STOP';

        html += `
            <div class="train-item ${typeClass} ${heldClass} ${activeClass}" data-train-id="${escapeHtml(train.id)}">
                <div class="train-info">
                    <span class="train-id">${escapeHtml(train.id)}</span>
                    <span class="train-type">${train.type === 'freight' ? 'FRT' : 'PAX'}</span>
                    <span class="train-location">${escapeHtml(train.segment || train.location || 'Unknown')}</span>
                </div>
                <span class="train-status ${statusClass}">${train.isHeld ? 'HELD' : train.status || 'Running'}</span>
                <div class="train-actions">
                    <button class="btn-emergency ${btnClass}" data-train-id="${escapeHtml(train.id)}" data-held="${train.isHeld ? 'true' : 'false'}">
                        ${btnText}
                    </button>
                </div>
            </div>
        `;
    }

    dispatcherTrainsList.innerHTML = html;

    // Add click handlers to train items
    dispatcherTrainsList.querySelectorAll('.train-item').forEach(item => {
        const trainId = item.dataset.trainId;

        // Click on train item to select
        item.addEventListener('click', (e) => {
            // Don't trigger if clicking on emergency button
            if (e.target.classList.contains('btn-emergency')) return;
            selectTrain(trainId);
        });
    });

    // Add click handlers to emergency buttons
    dispatcherTrainsList.querySelectorAll('.btn-emergency').forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            const trainId = btn.dataset.trainId;
            const isHeld = btn.dataset.held === 'true';

            if (isHeld) {
                // Release immediately without confirmation
                releaseEmergencyBrake(trainId);
            } else {
                // Show confirmation for emergency stop
                showEmergencyConfirmation(trainId);
            }
        });
    });
}

// ============================================
// EMERGENCY STOP CONFIRMATION MODAL
// ============================================

// Show emergency stop confirmation
function showEmergencyConfirmation(trainId) {
    pendingEmergencyTrainId = trainId;

    // Find train data
    const train = currentTrainData.find(t => t.id === trainId);
    const trainType = train ? (train.type === 'freight' ? 'Freight' : 'Passenger') : 'Unknown';
    const location = train ? (train.segment || train.location || 'Unknown') : 'Unknown';

    // Create modal if doesn't exist
    let modal = document.getElementById('confirm-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'confirm-modal';
        modal.className = 'confirm-modal';
        document.body.appendChild(modal);
    }

    modal.innerHTML = `
        <div class="confirm-dialog">
            <div class="confirm-icon">🚨</div>
            <div class="confirm-title">EMERGENCY STOP</div>
            <div class="confirm-message">
                Are you sure you want to emergency stop train<br>
                <span class="confirm-train-id">${escapeHtml(trainId)}</span>?<br><br>
                <small>Type: ${trainType} | Location: ${escapeHtml(location)}</small>
            </div>
            <div class="confirm-buttons">
                <button class="btn-confirm cancel" onclick="hideEmergencyConfirmation()">Cancel</button>
                <button class="btn-confirm danger" onclick="confirmEmergencyStop()">STOP TRAIN</button>
            </div>
        </div>
    `;

    modal.classList.add('visible');
    confirmModalVisible = true;
}

// Hide confirmation modal
function hideEmergencyConfirmation() {
    const modal = document.getElementById('confirm-modal');
    if (modal) {
        modal.classList.remove('visible');
    }
    confirmModalVisible = false;
    pendingEmergencyTrainId = null;
}

// Confirm and execute emergency stop
function confirmEmergencyStop() {
    if (!pendingEmergencyTrainId) return;

    const trainId = pendingEmergencyTrainId;
    hideEmergencyConfirmation();

    // Send to game client
    fetch(`https://${GetParentResourceName()}/emergencyStop`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trainId: trainId, action: 'stop' })
    });

    // Visual feedback
    const btn = document.querySelector(`.btn-emergency[data-train-id="${trainId}"]`);
    if (btn) {
        btn.classList.add('active');
        btn.textContent = 'STOPPING...';
        btn.disabled = true;
    }
}

// Release emergency brake
function releaseEmergencyBrake(trainId) {
    fetch(`https://${GetParentResourceName()}/emergencyStop`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trainId: trainId, action: 'release' })
    });

    // Visual feedback
    const btn = document.querySelector(`.btn-emergency[data-train-id="${trainId}"]`);
    if (btn) {
        btn.classList.remove('active');
        btn.textContent = 'RELEASING...';
        btn.disabled = true;
    }
}

// Make functions globally accessible for onclick handlers
window.hideEmergencyConfirmation = hideEmergencyConfirmation;
window.confirmEmergencyStop = confirmEmergencyStop;

// ============================================
// SEGMENT LOCK OVERRIDE (v2.6.0)
// ============================================

let contextMenuVisible = false;
let contextMenuSegmentId = null;
let lockReasonModalVisible = false;
let pendingLockSegmentId = null;

// Create context menu element
function createContextMenu() {
    let menu = document.getElementById('segment-context-menu');
    if (!menu) {
        menu = document.createElement('div');
        menu.id = 'segment-context-menu';
        menu.className = 'segment-context-menu';
        document.body.appendChild(menu);
    }
    return menu;
}

// Create lock reason modal
function createLockReasonModal() {
    let modal = document.getElementById('lock-reason-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'lock-reason-modal';
        modal.className = 'lock-reason-modal';
        modal.innerHTML = `
            <div class="lock-reason-dialog">
                <div class="lock-reason-title">
                    <span>🔒</span> Lock Segment
                </div>
                <div class="lock-reason-segment" id="lock-segment-name"></div>
                <input type="text" class="lock-reason-input" id="lock-reason-input"
                       placeholder="Enter reason (e.g., Maintenance, Police Activity)">
                <div class="lock-reason-buttons">
                    <button class="btn-cancel" onclick="hideLockReasonModal()">Cancel</button>
                    <button class="btn-lock" onclick="confirmSegmentLock()">Lock Segment</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
    }
    return modal;
}

// Show context menu on right-click
function showSegmentContextMenu(event, segmentId, segmentData) {
    event.preventDefault();
    event.stopPropagation();

    const menu = createContextMenu();
    contextMenuSegmentId = segmentId;
    contextMenuVisible = true;

    const isLocked = segmentData && segmentData.isLocked;
    const isOccupied = segmentData && segmentData.occupied;
    const segmentName = segmentData ? segmentData.name : segmentId;

    let menuItems = `<div class="context-menu-header">${escapeHtml(segmentName)}</div>`;

    if (isLocked) {
        // Show unlock option
        menuItems += `
            <div class="context-menu-item unlock" onclick="unlockSegment('${segmentId}')">
                <span class="item-icon">🔓</span>
                Unlock Segment
            </div>
        `;
        if (segmentData.lockReason) {
            menuItems += `
                <div class="context-menu-divider"></div>
                <div class="context-menu-item" style="color: #888; cursor: default; font-size: 11px;">
                    Reason: ${escapeHtml(segmentData.lockReason)}
                </div>
            `;
        }
    } else {
        // Show lock option
        menuItems += `
            <div class="context-menu-item lock" onclick="showLockReasonModal('${segmentId}', '${escapeHtml(segmentName)}')">
                <span class="item-icon">🔒</span>
                Lock Segment
            </div>
        `;
    }

    // If segment has a train, show additional options
    if (isOccupied && segmentData.trainId) {
        menuItems += `
            <div class="context-menu-divider"></div>
            <div class="context-menu-item" onclick="selectTrain('${segmentData.trainId}')">
                <span class="item-icon">🚂</span>
                Select Train
            </div>
        `;
    }

    menu.innerHTML = menuItems;

    // Position menu at cursor
    const x = Math.min(event.clientX, window.innerWidth - 200);
    const y = Math.min(event.clientY, window.innerHeight - 150);
    menu.style.left = x + 'px';
    menu.style.top = y + 'px';

    menu.classList.add('visible');
}

// Hide context menu
function hideContextMenu() {
    const menu = document.getElementById('segment-context-menu');
    if (menu) {
        menu.classList.remove('visible');
    }
    contextMenuVisible = false;
    contextMenuSegmentId = null;
}

// Show lock reason modal
function showLockReasonModal(segmentId, segmentName) {
    hideContextMenu();

    const modal = createLockReasonModal();
    pendingLockSegmentId = segmentId;

    document.getElementById('lock-segment-name').textContent = 'Segment: ' + segmentName;
    document.getElementById('lock-reason-input').value = '';

    modal.classList.add('visible');
    lockReasonModalVisible = true;

    // Focus input
    setTimeout(() => {
        document.getElementById('lock-reason-input').focus();
    }, 100);
}

// Hide lock reason modal
function hideLockReasonModal() {
    const modal = document.getElementById('lock-reason-modal');
    if (modal) {
        modal.classList.remove('visible');
    }
    lockReasonModalVisible = false;
    pendingLockSegmentId = null;
}

// Confirm segment lock
function confirmSegmentLock() {
    if (!pendingLockSegmentId) return;

    const reason = document.getElementById('lock-reason-input').value.trim() || 'Maintenance';

    fetch(`https://${GetParentResourceName()}/segmentOverride`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            segmentId: pendingLockSegmentId,
            action: 'lock',
            reason: reason
        })
    });

    hideLockReasonModal();
}

// Unlock segment directly
function unlockSegment(segmentId) {
    hideContextMenu();

    fetch(`https://${GetParentResourceName()}/segmentOverride`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            segmentId: segmentId,
            action: 'unlock'
        })
    });
}

// Handle segment override change from server
function handleSegmentOverrideChanged(data) {
    if (!data || !data.segmentId) return;

    const segmentEl = document.querySelector(`[data-segment="${data.segmentId}"]`);
    if (!segmentEl) return;

    const blockEl = segmentEl.querySelector('.segment-block');
    if (!blockEl) return;

    if (data.locked) {
        blockEl.classList.add('locked');
        // Update stored data
        if (currentSegmentData[data.segmentId]) {
            currentSegmentData[data.segmentId].isLocked = true;
            currentSegmentData[data.segmentId].lockReason = data.reason;
            currentSegmentData[data.segmentId].lockedBy = data.lockedBy;
        }
    } else {
        blockEl.classList.remove('locked');
        if (currentSegmentData[data.segmentId]) {
            currentSegmentData[data.segmentId].isLocked = false;
            currentSegmentData[data.segmentId].lockReason = null;
            currentSegmentData[data.segmentId].lockedBy = null;
        }
    }

    // Update tooltip
    updateSegmentTooltip(segmentEl, data.segmentId, currentSegmentData[data.segmentId] || {});
}

// Add right-click handler to segments (called during update)
function addSegmentContextMenuHandler(segmentEl, segmentId) {
    if (segmentEl.dataset.contextHandler) return;
    segmentEl.dataset.contextHandler = 'true';

    segmentEl.addEventListener('contextmenu', (e) => {
        const data = currentSegmentData[segmentId] || {};
        showSegmentContextMenu(e, segmentId, data);
    });
}

// Close context menu on click elsewhere
document.addEventListener('click', (e) => {
    if (contextMenuVisible && !e.target.closest('.segment-context-menu')) {
        hideContextMenu();
    }
});

// Handle Enter key in lock reason input
document.addEventListener('keydown', (e) => {
    if (lockReasonModalVisible && e.key === 'Enter') {
        confirmSegmentLock();
    }
});

// Make functions globally accessible
window.showLockReasonModal = showLockReasonModal;
window.hideLockReasonModal = hideLockReasonModal;
window.confirmSegmentLock = confirmSegmentLock;
window.unlockSegment = unlockSegment;

// Escape HTML for safety
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Close on ESC key
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        // Check if dispatcher is open
        if (dispatcherPanel && !dispatcherPanel.classList.contains('hidden')) {
            hideDispatcherPanel();
            // Notify game to release NUI focus
            fetch(`https://${GetParentResourceName()}/closeDispatcher`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            return;
        }

        // Close other UI elements
        hideScheduleBoard();
        hideTicket();

        // Notify game
        fetch(`https://${GetParentResourceName()}/close`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    }
});

// Get parent resource name (FiveM function)
function GetParentResourceName() {
    return window.GetParentResourceName ? window.GetParentResourceName() : 'dps-transit';
}

// ============================================
// SERVICE ALERTS & DELAY INFORMATION
// ============================================

let activeServiceAlert = null;
let currentDelays = {};

// Show service alert banner
function showServiceAlert(alertType, message, affectedLines) {
    let alertEl = document.getElementById('service-alert');

    // Create if doesn't exist
    if (!alertEl) {
        alertEl = document.createElement('div');
        alertEl.id = 'service-alert';
        alertEl.className = 'service-alert hidden';
        document.body.appendChild(alertEl);
    }

    // Determine alert styling based on type
    let alertClass = 'info';
    let icon = 'info-circle';

    switch (alertType) {
        case 'delay':
            alertClass = 'warning';
            icon = 'clock';
            break;
        case 'disruption':
            alertClass = 'error';
            icon = 'exclamation-triangle';
            break;
        case 'emergency':
            alertClass = 'emergency';
            icon = 'times-circle';
            break;
        case 'info':
        default:
            alertClass = 'info';
            icon = 'info-circle';
            break;
    }

    // Build affected lines string
    let linesStr = '';
    if (affectedLines && affectedLines.length > 0) {
        linesStr = affectedLines.join(', ');
    }

    alertEl.className = `service-alert ${alertClass}`;
    alertEl.innerHTML = `
        <div class="alert-content">
            <span class="alert-icon">${getAlertIcon(icon)}</span>
            <div class="alert-text">
                <div class="alert-title">${alertType.toUpperCase()}</div>
                <div class="alert-message">${message}</div>
                ${linesStr ? `<div class="alert-lines">Affected: ${linesStr}</div>` : ''}
            </div>
            <button class="alert-close" onclick="hideServiceAlert()">×</button>
        </div>
    `;

    alertEl.classList.remove('hidden');
    activeServiceAlert = { alertType, message, affectedLines };
}

// Hide service alert
function hideServiceAlert() {
    const alertEl = document.getElementById('service-alert');
    if (alertEl) {
        alertEl.classList.add('hidden');
    }
    activeServiceAlert = null;
}

// Get icon for alert type
function getAlertIcon(iconType) {
    switch (iconType) {
        case 'clock': return '⏱️';
        case 'exclamation-triangle': return '⚠️';
        case 'times-circle': return '❌';
        case 'info-circle':
        default: return 'ℹ️';
    }
}

// Update delay information for arrivals
function updateDelayInfo(delays) {
    currentDelays = delays || {};

    // Update any displayed arrivals with delay info
    const rows = document.querySelectorAll('.arrival-row');

    rows.forEach(row => {
        const destEl = row.querySelector('.col-dest');
        const statusEl = row.querySelector('.col-status');

        if (!destEl || !statusEl) return;

        const dest = destEl.textContent.trim();

        // Check if this destination has a delay
        for (const [trainId, delayInfo] of Object.entries(currentDelays)) {
            if (delayInfo.destination === dest && delayInfo.delayMinutes > 0) {
                statusEl.textContent = `+${delayInfo.delayMinutes} min`;
                statusEl.className = 'col-status delayed';
                break;
            }
        }
    });
}

// Add delay indicator to a specific train in arrivals
function addDelayIndicator(trainId, delayMinutes, reason) {
    currentDelays[trainId] = {
        delayMinutes,
        reason: reason || 'Service delay',
        timestamp: Date.now()
    };

    // Trigger UI update if schedule is visible
    if (!scheduleBoard.classList.contains('hidden')) {
        updateDelayInfo(currentDelays);
    }
}

// Clear delay for a train
function clearDelayIndicator(trainId) {
    delete currentDelays[trainId];
}

// Inject service alert styles
(function injectAlertStyles() {
    const style = document.createElement('style');
    style.textContent = `
        .service-alert {
            position: fixed;
            top: 10px;
            left: 50%;
            transform: translateX(-50%);
            min-width: 300px;
            max-width: 600px;
            padding: 12px 16px;
            border-radius: 8px;
            font-family: 'Roboto Mono', monospace;
            z-index: 1000;
            transition: opacity 0.3s, transform 0.3s;
        }

        .service-alert.hidden {
            opacity: 0;
            transform: translateX(-50%) translateY(-20px);
            pointer-events: none;
        }

        .service-alert.info {
            background: rgba(52, 152, 219, 0.95);
            border: 1px solid #2980b9;
            color: white;
        }

        .service-alert.warning {
            background: rgba(241, 196, 15, 0.95);
            border: 1px solid #f39c12;
            color: #2c3e50;
        }

        .service-alert.error {
            background: rgba(231, 76, 60, 0.95);
            border: 1px solid #c0392b;
            color: white;
        }

        .service-alert.emergency {
            background: rgba(155, 89, 182, 0.95);
            border: 1px solid #8e44ad;
            color: white;
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
        }

        .alert-content {
            display: flex;
            align-items: flex-start;
            gap: 12px;
        }

        .alert-icon {
            font-size: 24px;
            flex-shrink: 0;
        }

        .alert-text {
            flex-grow: 1;
        }

        .alert-title {
            font-weight: bold;
            font-size: 12px;
            letter-spacing: 1px;
            margin-bottom: 4px;
        }

        .alert-message {
            font-size: 14px;
        }

        .alert-lines {
            font-size: 11px;
            opacity: 0.8;
            margin-top: 4px;
        }

        .alert-close {
            background: transparent;
            border: none;
            color: inherit;
            font-size: 20px;
            cursor: pointer;
            opacity: 0.7;
            flex-shrink: 0;
        }

        .alert-close:hover {
            opacity: 1;
        }

        .col-status.delayed {
            color: #f39c12;
            font-weight: bold;
        }

        .col-status.emergency-stopped,
        .col-status.emergency_stopped {
            color: #e74c3c;
            font-weight: bold;
            animation: blink 1s infinite;
        }

        .col-status.waiting-junction,
        .col-status.waiting_junction {
            color: #9b59b6;
        }

        .col-status.resuming {
            color: #27ae60;
        }

        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }

        .arrival-row.fade-out {
            opacity: 0;
            transform: translateX(-20px);
            transition: opacity 0.3s, transform 0.3s;
        }

        .arrival-row {
            transition: opacity 0.2s, transform 0.2s;
        }
    `;
    document.head.appendChild(style);
})();
