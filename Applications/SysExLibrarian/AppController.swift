/*
 Copyright (c) 2002-2021, Kurt Revis.  All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Cocoa
import SnoizeMIDI

@objc class AppController: NSObject {

    override init() {
        super.init()
    }

    @objc private(set) var midiContext: MIDIContext?

    // MARK: Private
    private var hasFinishedLaunching = false
    private var filePathsToImport: [String] = []

}

extension AppController: NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Initialize CoreMIDI while the app's icon is still bouncing, so we don't have a large
        // pause after it stops bouncing but before the app's window opens.
        // (CoreMIDI needs to find and possibly start its server process, which can take a while.)
        let context = MIDIContext()
        midiContext = context
        if !context.connectedToCoreMIDI {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Error", tableName: "SysExLibrarian", bundle: Bundle.main, comment: "title of error alert")
            alert.informativeText = NSLocalizedString("There was a problem initializing the MIDI system. To try to fix this, log out and log back in, or restart the computer.", tableName: "SysExLibrarian", bundle: Bundle.main, comment: "error message if MIDI initialization fails")
            alert.addButton(withTitle: NSLocalizedString("Quit", tableName: "SysExLibrarian", bundle: Bundle.main, comment: "title of quit button"))

            _ = alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true

        guard let library = SSELibrary.shared() else { fatalError() }
        if let preflightErrorString = library.preflightAndLoadEntries() {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Error", tableName: "SysExLibrarian", bundle: Bundle.main, comment: "title of error alert")
            alert.informativeText = preflightErrorString
            alert.addButton(withTitle: NSLocalizedString("Quit", tableName: "SysExLibrarian", bundle: Bundle.main, comment: "title of quit button"))

            _ = alert.runModal()
            NSApp.terminate(nil)
        }
        else {
            showMainWindow(nil)

            if !filePathsToImport.isEmpty {
                importFiles()
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        filePathsToImport.append(filename)

        if hasFinishedLaunching {
            showMainWindow(nil)
            importFiles()
        }

        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            if let mainWindow = SSEMainWindowController.sharedInstance()?.window,
               mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
        }
        else {
            showMainWindow(nil)
        }

        return false
    }

}

extension AppController: NSUserInterfaceValidations {

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(self.showMainWindowAndAddToLibrary(_:)) {
            // Don't allow adds if the main window is open and has a sheet on it
            let mainWindow = SSEMainWindowController.sharedInstance()?.window
            return (mainWindow == nil || mainWindow!.attachedSheet == nil)
        }

        return true
    }

}

extension AppController /* Actions */ {

    @IBAction func showPreferences(_ sender: AnyObject?) {
        PreferencesWindowController.sharedInstance.showWindow(nil)
    }

    @IBAction func showAboutBox(_ sender: AnyObject?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]

        if #available(macOS 10.13, *) {
            options[NSApplication.AboutPanelOptionKey.version] = ""
        }
        else {
            // This works before the above API was available in 10.13
            options[NSApplication.AboutPanelOptionKey(rawValue: "Version")] = ""
        }

        // The RTF file Credits.rtf has foreground text color = black, but that's wrong for 10.14 dark mode.
        // Similarly the font is not necessarily the systme font. Override both.
        if #available(macOS 10.13, *) {
            if let creditsURL = Bundle.main.url(forResource: "Credits", withExtension: "rtf"),
               let credits = NSMutableAttributedString(url: creditsURL, documentAttributes: nil) {
                let range = NSRange(location: 0, length: credits.length)
                credits.addAttribute(.font, value: NSFont.labelFont(ofSize: NSFont.labelFontSize), range: range)
                if #available(macOS 10.14, *) {
                    credits.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
                options[NSApplication.AboutPanelOptionKey.credits] = credits
            }
        }

        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @IBAction func showHelp(_ sender: AnyObject?) {
        var message: String?

        if var url = SMBundleForObject(self).url(forResource: "docs", withExtension: "htmld") {
            url.appendPathComponent("index.html")
            if !NSWorkspace.shared.open(url) {
                message = NSLocalizedString("The help file could not be opened.", tableName: "MIDIMonitor", bundle: SMBundleForObject(self), comment: "error message if opening the help file fails")
            }
        }
        else {
            message = NSLocalizedString("The help file could not be found.", tableName: "MIDIMonitor", bundle: SMBundleForObject(self), comment: "error message if help file can't be found")
        }

        if let message = message {
            let title = NSLocalizedString("Error", tableName: "SysExLibrarian", bundle: SMBundleForObject(self), comment: "title of error alert")

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }
    }

    @IBAction func sendFeedback(_ sender: AnyObject?) {
        var success = false

        let feedbackEmailAddress = "SysExLibrarian@snoize.com"    // Don't localize this
        let feedbackEmailSubject = NSLocalizedString("SysEx Librarian Feedback", tableName: "SysExLibrarian", bundle: SMBundleForObject(self), comment: "subject of feedback email")
        let mailToURLString = "mailto:\(feedbackEmailAddress)?Subject=\(feedbackEmailSubject)"

        // Escape the whitespace characters in the URL before opening
        let allowedCharacterSet = CharacterSet.whitespaces.inverted
        if let escapedMailToURLString = mailToURLString.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet),
           let mailToURL = URL(string: escapedMailToURLString) {
            success = NSWorkspace.shared.open(mailToURL)
        }

        if !success {
            let message = NSLocalizedString("SysEx Librarian could not ask your email application to create a new message.\nPlease send email to:\n%@", tableName: "SysExLibrarian", bundle: SMBundleForObject(self), comment: "message of alert when can't send feedback email")

            let title = NSLocalizedString("Error", tableName: "SysExLibrarian", bundle: SMBundleForObject(self), comment: "title of error alert")

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = String.localizedStringWithFormat(message, feedbackEmailAddress)
            alert.runModal()
        }
    }

    @IBAction func showMainWindow(_ sender: AnyObject?) {
        guard let controller = SSEMainWindowController.sharedInstance() else { return }
        controller.showWindow(nil)
    }

    @IBAction func showMainWindowAndAddToLibrary(_ sender: AnyObject?) {
        guard let controller = SSEMainWindowController.sharedInstance() else { return }
        controller.showWindow(nil)
        controller.addToLibrary(sender)
    }

}

extension AppController /* Private */ {

    private func importFiles() {
        SSEMainWindowController.sharedInstance().importFiles(filePathsToImport, showingProgress: false)
        filePathsToImport = []
    }

}