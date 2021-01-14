/*
 Copyright (c) 2001-2021, Kurt Revis.  All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

@objc public class SMSystemExclusiveMessage: SMMessage {

    public init(timeStamp: MIDITimeStamp, data: Data) {
        self.data = data
        super.init(timeStamp: timeStamp, statusByte: 0xF0)
    }

    public required init?(coder: NSCoder) {
        if let data = coder.decodeObject(forKey: "data") as? Data {
            self.data = data
        }
        else {
            return nil
        }
        wasReceivedWithEOX = coder.decodeBool(forKey: "wasReceivedWithEOX")
        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(data, forKey: "data")
        coder.encode(wasReceivedWithEOX, forKey: "wasReceivedWithEOX")
    }

    // MARK: Public

    // Data *without* the starting 0xF0 or ending 0xF7 (EOX).
    @objc public var data: Data {
        didSet {
            cachedDataWithEOX = nil
        }
    }

    // Whether the message was received with an ending 0xF7 (EOX) or not.
    @objc public var wasReceivedWithEOX = false

    // Data without the starting 0xF0, always with ending 0xF7.
    public override var otherData: Data! {
        if cachedDataWithEOX == nil {
            cachedDataWithEOX = data
            cachedDataWithEOX?.append(0xF7)
        }
        return cachedDataWithEOX
    }

    public override var otherDataLength: Int {
        data.count + 1  // Add a byte for the EOX at the end
    }

    // Data as received, without starting 0xF0. May or may not include 0xF7.
    @objc public var receivedData: Data {
        wasReceivedWithEOX ? otherData : data
    }

    @objc public var receivedDataLength: Int {
        receivedData.count
    }

    // Data as received, with 0xF0 at start. May or may not include 0xF7.
    @objc public var receivedDataWithStartByte: Data {
        dataByAddingStartByte(data)
    }

    @objc public var receivedDataWithStartByteLength: Int {
        receivedDataLength + 1
    }

    // Data with leading 0xF0 and ending 0xF7.
    @objc public var fullMessageData: Data {
        dataByAddingStartByte(otherData)
    }

    @objc public var fullMessageDataLength: Int {
        otherDataLength + 1
    }

    // Manufacturer ID bytes. May be 1 to 3 bytes in length, or nil if it can't be determined.
    @objc public var manufacturerIdentifier: Data? {
        guard data.count > 0 else { return nil }

        // If the first byte is not 0, the manufacturer ID is one byte long. Otherwise, return a three-byte value (if possible).
        if data[0] != 0 {
            return data.subdata(in: 0..<1)
        }
        else if data.count >= 3 {
            return data.subdata(in: 0..<3)
        }
        else {
            return nil
        }
    }

    @objc public var manufacturerName: String? {
        guard let identifier = manufacturerIdentifier else { return nil }
        return SMMessage.name(forManufacturerIdentifier: identifier)
    }

    @objc public var sizeForDisplay: String {
        guard let formattedLength = SMMessage.formatLength(receivedDataWithStartByteLength) else { return "" }
        let format = NSLocalizedString("%@ bytes", tableName: "SnoizeMIDI", bundle: SMBundleForObject(self), comment: "SysEx length format string")
        return String.localizedStringWithFormat(format, formattedLength)
    }

    // MARK: Private

    private var cachedDataWithEOX: Data?

    private func dataByAddingStartByte(_ someData: Data) -> Data {
        var result = someData
        result.insert(0xF0, at: 0)
        return result
    }

    // MARK: SMMessage overrides

    public override var messageType: SMMessageType {
        SMMessageTypeSystemExclusive
    }

    public override var typeForDisplay: String! {
        NSLocalizedString("SysEx", tableName: "SnoizeMIDI", bundle: SMBundleForObject(self), comment: "displayed type of System Exclusive event")
    }

    public override var dataForDisplay: String! {
        var result = ""
        if let name = manufacturerName {
            result += name + " "
        }
        result += sizeForDisplay
        if let dataString = expertDataForDisplay {
            result += "\t" + dataString
        }
        return result
    }

}

extension SMSystemExclusiveMessage {

    // Convert an array of sysex messages to a single chunk of data (e.g. for a .syx file),
    // and vice-versa.

    @objc public static func messages(fromData data: Data) -> [SMSystemExclusiveMessage] {
        // Scan through data and make messages out of it.
        // Messages must start with 0xF0.  Messages may end in any byte >= 0x80.

        var messages: [SMSystemExclusiveMessage] = []

        var inMessage = false
        var messageDataBounds = (lower: data.startIndex, upper: data.startIndex)

        func addMessageIfPossible() {
            let range = messageDataBounds.lower ..< messageDataBounds.upper
            if !range.isEmpty {
                let sysexData = data.subdata(in: range)
                let message = SMSystemExclusiveMessage(timeStamp: 0, data: sysexData)
                messages.append(message)
            }
        }

        for (index, byte) in data.enumerated() {
            if inMessage && byte >= 0x80 {
                // end of the current message
                messageDataBounds.upper = index
                addMessageIfPossible()
                inMessage = false
            }

            if byte == 0xF0 {
                // start of the next message
                inMessage = true
                messageDataBounds.lower = index + 1
            }
        }

        if inMessage {
            messageDataBounds.upper = data.endIndex
            addMessageIfPossible()
        }

        return messages
    }

    @objc public static func data(forMessages messages: [SMSystemExclusiveMessage]) -> Data? {
        guard messages.count > 0 else { return nil }

        var resultData = Data()

        // Reserve capacity for all the data up front, before concatenating.
        // Each message is represented as 0xF0 + message.data + 0xF7
        var totalCount: Int = 0
        for message in messages {
            totalCount += 1 + message.data.count + 1
        }
        resultData.reserveCapacity(totalCount)

        for message in messages {
            resultData.append(0xF0)
            resultData.append(message.data)
            resultData.append(0xF7)
        }

        return resultData
    }

}

import AudioToolbox

extension SMSystemExclusiveMessage {

    // Extract sysex messages from a Standard MIDI file, and vice-versa.

    @objc public static func messages(fromStandardMIDIFileData data: Data) -> [SMSystemExclusiveMessage] {
        var possibleSequence: MusicSequence?
        guard NewMusicSequence(&possibleSequence) == noErr, let sequence = possibleSequence else { return [] }
        defer { _ = DisposeMusicSequence(sequence) }

        guard MusicSequenceFileLoadData(sequence, data as CFData, .midiType, .smf_ChannelsToTracks) == noErr else { return [] }

        var messages: [SMSystemExclusiveMessage] = []

        // The last track should contain any sysex data.
        var trackCount: UInt32 = 0
        if MusicSequenceGetTrackCount(sequence, &trackCount) == noErr {
            var possibleTrack: MusicTrack?
            if MusicSequenceGetIndTrack(sequence, trackCount - 1, &possibleTrack) == noErr,
               let track = possibleTrack {
                // Iterate through the events, looking for MIDI "raw data" events, which may contain sysex data.
                // (The names get confusing, because we use Swift's "raw pointers" to get to the data
                // from this old C-based API.)

                var possibleIterator: MusicEventIterator?
                if NewMusicEventIterator(track, &possibleIterator) == noErr,
                   let iterator = possibleIterator {
                    defer { _ = DisposeMusicEventIterator(iterator) }

                    var hasCurrentEvent: DarwinBoolean = false
                    MusicEventIteratorHasCurrentEvent(iterator, &hasCurrentEvent)
                    while hasCurrentEvent.boolValue {
                        var timeStamp: MusicTimeStamp = 0   // ignored
                        var eventType: MusicEventType = kMusicEventType_NULL
                        var eventData: UnsafeRawPointer?
                        var eventDataSize: UInt32 = 0

                        let status = MusicEventIteratorGetEventInfo(iterator, &timeStamp, &eventType, &eventData, &eventDataSize)

                        if status == noErr && eventType == kMusicEventType_MIDIRawData && eventDataSize > 0,
                           let eventData = eventData {
                            // eventData is a pointer to a MIDIRawData struct. That just contains
                            // another length field and then the "raw" MIDI data.
                            let midiRawDataEventPtr = eventData.bindMemory(to: MIDIRawData.self, capacity: Int(eventDataSize))
                            let midiRawDataLength = Int(midiRawDataEventPtr.pointee.length)
                            withUnsafePointer(to: midiRawDataEventPtr.pointee.data) { midiRawDataPtr in
                                let midiRawData = Data(UnsafeBufferPointer(start: midiRawDataPtr, count: midiRawDataLength))
                                let eventMessages = Self.messages(fromData: midiRawData)
                                // TODO Check that this is sufficient. Can we have sysex messages that are split across multiple MIDIRawData events? I bet we can, and the old code handled it.

                                messages.append(contentsOf: eventMessages)
                            }
                        }

                        _ = MusicEventIteratorNextEvent(iterator)
                        _ = MusicEventIteratorHasCurrentEvent(iterator, &hasCurrentEvent)
                    }
                }
            }
        }

        return messages
    }

    @objc public static func standardMIDIFileData(forMessages messages: [SMSystemExclusiveMessage]) -> Data? {
        guard messages.count > 0 else { return nil }

        var possibleSequence: MusicSequence?
        guard NewMusicSequence(&possibleSequence) == noErr, let sequence = possibleSequence else { return nil }
        defer { _ = DisposeMusicSequence(sequence) }

        var possibleTrack: MusicTrack?
        guard MusicSequenceNewTrack(sequence, &possibleTrack) == noErr, let track = possibleTrack else { return nil }

        var timeStamp: MusicTimeStamp = 0
        for message in messages {
            let messageData = message.fullMessageData

            // Create a buffer large enough for a MIDIRawData struct containing all messageData
            let structCount = MemoryLayout.offset(of: \MIDIRawData.data)! + messageData.count
            let mutableRawPointer = UnsafeMutableRawPointer.allocate(byteCount: structCount, alignment: MemoryLayout<MIDIRawData>.alignment)
            defer { mutableRawPointer.deallocate() }

            let midiRawDataPtr = mutableRawPointer.bindMemory(to: MIDIRawData.self, capacity: structCount)
            midiRawDataPtr.pointee.length = UInt32(messageData.count)
            messageData.copyBytes(to: &midiRawDataPtr.pointee.data, count: messageData.count)

            guard MusicTrackNewMIDIRawDataEvent(track, timeStamp, midiRawDataPtr) == noErr else { return nil }

            timeStamp += 500    // TODO Are we sure?
            // consider getting a duration with bytes/3125, then MusicSequenceGetBeatsForSeconds()
        }

        var unmanagedResultData: Unmanaged<CFData>?
        guard MusicSequenceFileCreateData(sequence, .midiType, MusicSequenceFileFlags(rawValue: 0), 0 /* TODO or 480? */, &unmanagedResultData) == noErr else { return nil }
        return unmanagedResultData?.takeRetainedValue() as Data?
    }

}
