/*
 Copyright (c) 2001-2021, Kurt Revis.  All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import CoreMIDI

protocol CoreMIDIContext: AnyObject {

    var interface: CoreMIDIInterface { get }

    var midiClient: MIDIClientRef { get }

    func refreshEndpointsForDevice(_ device: Device)

    func generateNewUniqueID() -> MIDIUniqueID

    func addVirtualSource(midiObjectRef: MIDIObjectRef) -> Source?
    func addVirtualDestination(midiObjectRef: MIDIObjectRef) -> Destination?

}

class MIDIContext: CoreMIDIContext {

    private init?(interface: CoreMIDIInterface = RealCoreMIDIInterface()) {
        checkMainQueue()

        self.interface = interface

        var createdSelf: MIDIContext?

        let status: OSStatus
        if #available(macOS 10.11, iOS 9.0, *) {
            status = interface.clientCreateWithBlock(name as CFString, &midiClient) { unsafeNotification in
                // Note: We can't capture `self` in here, since we aren't yet fully initialized.
                // Also note that we are called on an arbitrary queue, so we need to dispatch to the main queue for later handling.
                // But `unsafeNotification` is only valid during this function call.

                // TODO In practice this sometimes comes in on the main queue,
                // so perhaps optimize for that?
                if let ourNotification = ContextNotification.fromCoreMIDI(unsafeNotification) {
                    DispatchQueue.main.async {
                        if let context = createdSelf {
                            context.handle(ourNotification)
                        }
                    }
                }
            }
        }
        else {
            // TODO Work out how to fix this w/o being able to pass self.
            // Need to, I suppose, make a test client then make another one?
            fatalError()
            /*
            status = MIDIClientCreate(name as CFString, { (unsafeNotification, _) in
                // As above, we can't use the refCon to stash a pointer to self, because
                // when we create the client, self isn't done being initialized yet.
                // We assume CoreMIDI is following its documentation, calling us "on the run loop which
                // was current when MIDIClientCreate was first called", which must be the main queue's run loop.
                let ourNotification = SMClientNotification.fromCoreMIDINotification(unsafeNotification)
                if let client = SMClient.sharedClient {
                    ourNotification.dispatchToClient(client)
                }
            }, nil, &midiClient)
             */
        }

        if status != noErr {
            return nil
        }

        createdSelf = self
    }

    // MARK: CoreMIDIContext

    public let interface: CoreMIDIInterface

    var midiClient: MIDIClientRef = 0

    func refreshEndpointsForDevice(_ device: Device) {
        // TODO This is an overly blunt approach, can we do better by using the device?
        sourceList.refreshAllObjects()
        destinationList.refreshAllObjects()
    }

    func generateNewUniqueID() -> MIDIUniqueID {
        while true {
            // We could get fancy, but just using the current time is likely to work just fine.
            // Add a sequence number in case this method is called more than once within a second.
            let proposed: MIDIUniqueID = Int32(time(nil)) + uniqueIDSequence
            uniqueIDSequence += 1

            if !isUniqueIDUsed(proposed) {
                return proposed
            }
        }
    }

    // MARK: Other API

    //    @objc public var postsExternalSetupChangeNotification = true    // TODO Should this be public? Seems like an internal detail
    //    @objc public private(set) var isHandlingSetupChange = false

    //    public func forceCoreMIDIToUseNewSysExSpeed() {
    //        // The CoreMIDI client caches the last device that was given to MIDISendSysex(), along with its max sysex speed.
    //        // So when we change the speed, it doesn't notice and continues to use the old speed.
    //        // To fix this, we send a tiny sysex message to a different device.  Unfortunately we can't just use a NULL endpoint,
    //        // it has to be a real live endpoint.
    //
    //        // TODO None of this code is marked as actually throwing -- resolve that
    //        do {
    //            if let endpoint = SMDestinationEndpoint.sysExSpeedWorkaroundEndpoint {
    //               let message = SMSystemExclusiveMessage(timeStamp: 0, data: Data())
    //                _ = SMSysExSendRequest(message: message, endpoint: endpoint)?.send()
    //            }
    //        }
    //        catch {
    //            // don't care
    //        }
    //    }

    public func disconnect() {
        // Disconnect from CoreMIDI. Necessary only for very special circumstances, since CoreMIDI will be unusable afterwards.
        _ = interface.clientDispose(midiClient)
        midiClient = 0
    }

    // MARK: Private

    private let name =
        (Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String) ?? ProcessInfo.processInfo.processName

    private var uniqueIDSequence: Int32 = 0

    private func isUniqueIDUsed(_ uniqueID: MIDIUniqueID) -> Bool {
        var objectRef: MIDIObjectRef = 0
        var objectType: MIDIObjectType = .other

        return interface.objectFindByUniqueID(uniqueID, &objectRef, &objectType) == noErr && objectRef != 0
    }

    // MARK: Notifications

    private enum ContextNotification {

        case added(object: MIDIObjectRef, objectType: MIDIObjectType, parent: MIDIObjectRef, parentType: MIDIObjectType)
        case removed(object: MIDIObjectRef, objectType: MIDIObjectType, parent: MIDIObjectRef, parentType: MIDIObjectType)
        case propertyChanged(object: MIDIObjectRef, objectType: MIDIObjectType, property: CFString)

        static func fromCoreMIDI(_ unsafeCoreMIDINotification: UnsafePointer<MIDINotification>) -> Self? {
            switch unsafeCoreMIDINotification.pointee.messageID {
            case .msgObjectAdded:
                let addRemoveNotification = UnsafeRawPointer(unsafeCoreMIDINotification).load(as: MIDIObjectAddRemoveNotification.self)
                return .added(object: addRemoveNotification.child, objectType: addRemoveNotification.childType, parent: addRemoveNotification.parent, parentType: addRemoveNotification.parentType)

            case .msgObjectRemoved:
                let addRemoveNotification = UnsafeRawPointer(unsafeCoreMIDINotification).load(as: MIDIObjectAddRemoveNotification.self)
                return .removed(object: addRemoveNotification.child, objectType: addRemoveNotification.childType, parent: addRemoveNotification.parent, parentType: addRemoveNotification.parentType)

            case .msgPropertyChanged:
                let propertyChangedNotification = UnsafeRawPointer(unsafeCoreMIDINotification).load(as: MIDIObjectPropertyChangeNotification.self)
                return .propertyChanged(object: propertyChangedNotification.object, objectType: propertyChangedNotification.objectType, property: propertyChangedNotification.propertyName.takeUnretainedValue())

            default:
                return nil
            }
        }

    }

    private func handle(_ notification: ContextNotification) {
        checkMainQueue()
        switch notification {
        case .added(let object, let objectType, let parent, let parentType):
            midiObjectList(type: objectType)?.objectWasAdded(
                midiObjectRef: object,
                parentObjectRef: parent,
                parentType: parentType
            )

        case .removed(let object, let objectType, let parent, let parentType):
            midiObjectList(type: objectType)?.objectWasRemoved(
                midiObjectRef: object,
                parentObjectRef: parent,
                parentType: parentType
            )

        case .propertyChanged(let object, let objectType, let property):
            midiObjectList(type: objectType)?.objectPropertyChanged(
                midiObjectRef: object,
                property: property
            )
        }
    }

    // MARK: Object lists

    private lazy var deviceList = MIDIObjectList<Device>(self)
    private lazy var externalDeviceList = MIDIObjectList<ExternalDevice>(self)
    private lazy var sourceList = MIDIObjectList<Source>(self)
    private lazy var destinationList = MIDIObjectList<Destination>(self)

    private lazy var midiObjectListsByType: [MIDIObjectType: CoreMIDIObjectList] = {
        let lists: [CoreMIDIObjectList] = [deviceList, externalDeviceList, sourceList, destinationList]
        return Dictionary(uniqueKeysWithValues: lists.map({ ($0.midiObjectType, $0) }))
    }()

    private func midiObjectList(type: MIDIObjectType) -> CoreMIDIObjectList? {
        midiObjectListsByType[type]
    }

    func addVirtualSource(midiObjectRef: MIDIObjectRef) -> Source? {
        sourceList.objectWasAdded(midiObjectRef: midiObjectRef, parentObjectRef: 0, parentType: .other)
        return sourceList.findObject(objectRef: midiObjectRef)
    }

    func addVirtualDestination(midiObjectRef: MIDIObjectRef) -> Destination? {
        destinationList.objectWasAdded(midiObjectRef: midiObjectRef, parentObjectRef: 0, parentType: .other)
        return destinationList.findObject(objectRef: midiObjectRef)
    }

}

private func checkMainQueue() {
    if #available(macOS 10.12, iOS 10.0, *) {
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    }
    else {
        assert(Thread.isMainThread)
    }
}