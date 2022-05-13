/**
 * Copyright (c) 2017 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import Cocoa

class ViewController: NSViewController {

    // MARK: - Outlets

    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var infoTextView: NSTextView!
    @IBOutlet weak var saveInfoButton: NSButton!
    @IBOutlet weak var moveUpButton: NSButton!

    // MARK: - Properties

    var filesList: [URL] = []
    var showInvisibles = false

    var selectedFolder: URL? {
        didSet {
            if let selectedFolder = selectedFolder {
                filesList = contentsOf(folder: selectedFolder)
                selectedItem = nil
                self.tableView.reloadData()
                self.tableView.scrollRowToVisible(0)
                moveUpButton.isEnabled = true
                view.window?.title = selectedFolder.path
            } else {
                moveUpButton.isEnabled = false
                view.window?.title = "FileSpy"
            }
        }
    }

    var selectedItem: URL? {
        didSet {
            infoTextView.string = ""
            saveInfoButton.isEnabled = false

            guard let selectedUrl = selectedItem else {
                return
            }

            let infoString = infoAbout(url: selectedUrl)
            if !infoString.isEmpty {
                let formattedText = formatInfoText(infoString)
                infoTextView.textStorage?.setAttributedString(formattedText)
                saveInfoButton.isEnabled = true
            }
        }
    }

// MARK: - View Lifecycle & error dialog utility

    override func viewWillAppear() {
        super.viewWillAppear()

        restoreCurrentSelections()
    }

    override func viewWillDisappear() {
        saveCurrentSelections()

        super.viewWillDisappear()
    }

    func showErrorDialogIn(window: NSWindow, title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}

// MARK: - Getting file or folder information

extension ViewController {

    func contentsOf(folder: URL) -> [URL] {
        let fileManager = FileManager.default
        do {
            if !folder.startAccessingSecurityScopedResource() {
                print("startAccessingSecurityScopedResource returned false. This directory might not need it, or this URL might not be a security scoped URL, or maybe something's wrong?")
            }
            let contents = try fileManager.contentsOfDirectory(atPath: folder.path)
            let urls = contents
                .filter { return showInvisibles ? true : $0.first != "." }
                .map { return folder.appendingPathComponent($0) }
            
            folder.stopAccessingSecurityScopedResource()
            return urls
        } catch {
            return []
        }
    }

    func infoAbout(url: URL) -> String {
        let fileManager = FileManager.default

        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            var report: [String] = ["\(url.path)", ""]

            for (key, value) in attributes {
                // ignore NSFileExtendedAttributes as it is a messy dictionary
                if key.rawValue == "NSFileExtendedAttributes" { continue }
                report.append("\(key.rawValue):\t \(value)")
            }
            return report.joined(separator: "\n")
        } catch {
            return "No information available for \(url.path)"
        }
    }

    func formatInfoText(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle
        paragraphStyle?.minimumLineHeight = 24
        paragraphStyle?.alignment = .left
        paragraphStyle?.tabStops = [ NSTextTab(type: .leftTabStopType, location: 240) ]

        let textAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 14),
            NSAttributedString.Key.paragraphStyle: paragraphStyle ?? NSParagraphStyle.default
        ]

        let formattedText = NSAttributedString(string: text, attributes: textAttributes)
        return formattedText
    }

    private func restoreFileAccess(with bookmarkData: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // bookmarks could become stale as the OS changes
                print("Bookmark is stale, need to save a new one... ")
                saveBookmarkData(for: url)
            }
            return url
        } catch {
            print("Error resolving bookmark:", error)
            return nil
        }
    }

    private func saveBookmarkData(for workDir: URL) {
        do {
            let bookmarkData = try workDir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

            // save in UserDefaults
//            Preferences.workingDirectoryBookmark = bookmarkData
            let userDefault = UserDefaults.standard
            
            userDefault.set(bookmarkData, forKey: "workingDirectoryBookmark")
            userDefault.synchronize()
        } catch {
            print("Failed to save bookmark data for \(workDir)", error)
        }
    }
}

// MARK: - Actions

extension ViewController {

    @IBAction func selectFolderClicked(_ sender: Any) {
        guard let window = view.window else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window) { (result) in
            if result == NSApplication.ModalResponse.OK {
                self.selectedFolder = panel.urls[0]
                self.saveBookmarkData(for: self.selectedFolder!)
            }
        }
    }

    @IBAction func toggleShowInvisibles(_ sender: NSButton) {
        showInvisibles = (sender.state == NSControl.StateValue.on)
        if let selectedFolder = selectedFolder {
            filesList = contentsOf(folder: selectedFolder)
            selectedItem = nil
            tableView.reloadData()
        }
    }

    @IBAction func tableViewDoubleClicked(_ sender: Any) {
        if tableView.selectedRow < 0 { return }

        let selectedItem = filesList[tableView.selectedRow]
        if selectedItem.hasDirectoryPath {
            selectedFolder = selectedItem
        }
    }

    @IBAction func moveUpClicked(_ sender: Any) {
        if selectedFolder?.path == "/" { return }
        selectedFolder = selectedFolder?.deletingLastPathComponent()
    }

    @IBAction func saveInfoClicked(_ sender: Any) {
        guard let window = view.window else { return }
        guard let selectedUrl = selectedItem else { return }

        let panel = NSSavePanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.nameFieldStringValue = selectedUrl
                .deletingPathExtension()
                .appendingPathExtension("fs.txt")
                .lastPathComponent

        panel.beginSheetModal(for: window) { (result) in
        if result == NSApplication.ModalResponse.OK,
            let url = panel.url {
                do {
                    let infoAsText = self.infoAbout(url: selectedUrl)
                    try infoAsText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self.showErrorDialogIn(window: window,
                                 title: "Unable to save file",
                                 message: error.localizedDescription)
                }
            }
        }
    }

}

// MARK: - NSTableViewDataSource

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filesList.count
    }
}

// MARK: - NSTableViewDelegate

extension ViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor
        tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filesList[row]

        let fileIcon = NSWorkspace.shared.icon(forFile: item.path)

        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FileCell"), owner: nil)
                as? NSTableCellView {
            cell.textField?.stringValue = item.lastPathComponent
            cell.imageView?.image = fileIcon
            return cell
        }

        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if tableView.selectedRow < 0 {
            selectedItem = nil
            return
        }

        selectedItem = filesList[tableView.selectedRow]
    }
}

// MARK: - Save & Restore previous selection

extension ViewController {

    func saveCurrentSelections() {
        guard let dataFileUrl = urlForDataStorage() else { return }

        let parentForStorage = selectedFolder?.path ?? ""
        let fileForStorage = selectedItem?.path ?? ""
        let completeData = "\(parentForStorage)\n\(fileForStorage)\n"

        try? completeData.write(to: dataFileUrl, atomically: true, encoding: .utf8)
    }

    func restoreCurrentSelections() {
        guard let dataFileUrl = urlForDataStorage() else { return }

        do {
            let storedData = try String(contentsOf: dataFileUrl)
            let storedDataComponents = storedData.components(separatedBy: .newlines)
            
            let userDefault = UserDefaults.standard
            
            if storedDataComponents.count >= 2 {
                if !storedDataComponents[0].isEmpty {
                    selectedFolder = URL(fileURLWithPath: storedDataComponents[0])
                    if let bookmarkData = userDefault.data(forKey: "workingDirectoryBookmark") {
                        selectedFolder = self.restoreFileAccess(with: bookmarkData)
                    }
                    if !storedDataComponents[1].isEmpty {
                        selectedItem = URL(fileURLWithPath: storedDataComponents[1])
                        selectUrlInTable(selectedItem)
                    }
                }
            }
        } catch {
            print(error)
        }
    }

    private func selectUrlInTable(_ url: URL?) {
        guard let url = url else {
            tableView.deselectAll(nil)
            return
        }

        if let rowNumber = filesList.index(of: url) {
            let indexSet = IndexSet(integer: rowNumber)
            DispatchQueue.main.async {
                self.tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
            }
        }
    }

    private func urlForDataStorage() -> URL? {
        let fileManager = FileManager.default
        guard let folder = fileManager.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first else {
                                          return nil
        }
        let appFolder = folder.appendingPathComponent("FileSpy")

        var isDirectory: ObjCBool = false
        let folderExists = fileManager.fileExists(atPath: appFolder.path, isDirectory: &isDirectory)
        if !folderExists || !isDirectory.boolValue {
            do {
                try fileManager.createDirectory(at: appFolder,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            } catch {
                return nil
            }
        }
    
        let dataFileUrl = appFolder.appendingPathComponent("StoredState.txt")
        return dataFileUrl
    }
}
