import Foundation

@MainActor
final class MusicProvider: ObservableObject {
    @Published private(set) var trackName = ""
    @Published private(set) var artistName = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var lyrics = ""
    @Published private(set) var playerName = ""

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        if trySpotify() { return }
        if tryAppleMusic() { return }
        trackName = ""
        artistName = ""
        isPlaying = false
        lyrics = ""
        playerName = ""
    }

    private func trySpotify() -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return "NOT_RUNNING"
        end tell
        tell application "Spotify"
            if player state is playing then
                set t to name of current track
                set a to artist of current track
                return t & "|" & a & "|playing"
            else if player state is paused then
                set t to name of current track
                set a to artist of current track
                return t & "|" & a & "|paused"
            else
                return "STOPPED"
            end if
        end tell
        """
        let result = runAppleScript(script)
        if result == "NOT_RUNNING" || result == "STOPPED" || result.isEmpty { return false }
        let parts = result.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        trackName = String(parts[0])
        artistName = String(parts[1])
        isPlaying = parts[2] == "playing"
        playerName = "Spotify"
        lyrics = ""
        return true
    }

    private func tryAppleMusic() -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return "NOT_RUNNING"
        end tell
        tell application "Music"
            if player state is playing then
                set t to name of current track
                set a to artist of current track
                set l to ""
                try
                    set l to lyrics of current track
                end try
                return t & "|" & a & "|playing|" & l
            else if player state is paused then
                set t to name of current track
                set a to artist of current track
                set l to ""
                try
                    set l to lyrics of current track
                end try
                return t & "|" & a & "|paused|" & l
            else
                return "STOPPED"
            end if
        end tell
        """
        let result = runAppleScript(script)
        if result == "NOT_RUNNING" || result == "STOPPED" || result.isEmpty { return false }
        let parts = result.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        trackName = String(parts[0])
        artistName = String(parts[1])
        isPlaying = parts[2] == "playing"
        playerName = "Apple Music"
        lyrics = parts.count >= 4 ? String(parts[3]) : ""
        return true
    }

    func togglePlayPause() {
        switch playerName {
        case "Spotify":
            runAppleScript("tell application \"Spotify\" to playpause")
        default:
            runAppleScript("tell application \"Music\" to playpause")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func nextTrack() {
        switch playerName {
        case "Spotify":
            runAppleScript("tell application \"Spotify\" to next track")
        default:
            runAppleScript("tell application \"Music\" to next track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func previousTrack() {
        switch playerName {
        case "Spotify":
            runAppleScript("tell application \"Spotify\" to previous track")
        default:
            runAppleScript("tell application \"Music\" to previous track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String {
        guard let script = NSAppleScript(source: source) else { return "" }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return "" }
        return result.stringValue ?? ""
    }
}
