/*
 Copyright (c) 2021, Kurt Revis.  All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import CoreMIDI

class Source: Endpoint, CoreMIDIObjectListable {

    // MARK: CoreMIDIObjectListable

    static let midiObjectType = MIDIObjectType.source
    static func midiObjectCount(_ context: CoreMIDIContext) -> Int {
        context.interface.getNumberOfSources()
    }
    static func midiObjectSubscript(_ context: CoreMIDIContext, _ index: Int) -> MIDIObjectRef {
        context.interface.getSource(index)
    }

    // MARK: New API

    // TODO endpointCount(forEntity), endpointRef(atIndex: forEntity)
}

extension CoreMIDIContext {

    public func createVirtualSource(name: String, uniqueID: MIDIUniqueID) -> Source? {
        // If newUniqueID is 0, we'll use the unique ID that CoreMIDI generates for us

        // We are going to be making a lot of changes, so turn off external notifications
        // for a while (until we're done).  Internal notifications are still necessary and aren't very slow.
        // TODO Do that again, if necessary

        var newEndpointRef: MIDIEndpointRef = 0
        guard interface.sourceCreate(midiClient, name as CFString, &newEndpointRef) == noErr else { return nil }

        // We want to get at the Source immediately, to configure it.
        // CoreMIDI will send us a notification that something was added,
        // but that won't arrive until later. So manually add the new Source,
        // trusting that we won't add it again later.
        guard let source = addVirtualSource(midiObjectRef: newEndpointRef) else { return nil }

        source.setOwnedByThisProcess()

        if uniqueID != 0 {
            source.uniqueID = uniqueID
        }
        while source.uniqueID == 0 {
            // CoreMIDI didn't assign a unique ID to this endpoint, so we should generate one ourself
            source.uniqueID = generateNewUniqueID()
        }

        source.manufacturer = "Snoize"
        source.model = name

        return source
    }

}