//
//  ContentView.swift
//  bleper
//
//  Created by 新妻浩光 on 2023/10/12.
//

import SwiftUI
import Foundation
import CoreBluetooth
import os
import DequeModule
import MusicKit
import MediaPlayer
class PeripheralViewModel: NSObject, ObservableObject {
    private let serviceCBUUID:CBUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    private let characteristicCBUUID:CBUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    @Published var message: String = ""
    @Published var toggleFrag: Bool = false
    @Published var status: String = ""
    @Published var keycode: String = "---"
    @Published var chords: String = ""
    var lastCord:String = ""
    var peripheralManager: CBPeripheralManager!
    var transferCharacteristic: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    var dataToSend = Data()
    var sendDataIndex: Int = 0
    var filelistcount:Int=0
    var flagSplit:Bool = false
    @Published var isReceiveMidi = false
    @Published var midiComplete = false
    @Published var progressReceiveMidi:String = ""
    @Published var TotalReceiveMidi:UInt64 = 0
    @Published var receivingMidiFile:String = ""
    @Published var receiveMessage = ""
    @Published var savemidifilename = ""
    var recvFile: Deque<UInt8> = []
    var recvQ: Deque<UInt8> = []
    var sendQ: Deque< Data > = []
    var messages: Deque< Deque<UInt8?> > = []
    var timeQue:Deque<UInt16> = []
    var lastTimestamp:UInt16 = 0
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    func switchChanged() {
        if toggleFrag {
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceCBUUID] ,CBAdvertisementDataLocalNameKey:"ChordTracker SinkerBLE" ] )
            status = "待受中 ChordTrackerから接続してください"
        } else {
            status = "待受中止中"
            stopAction()
        }
    }
    
    func stopAction() {
        peripheralManager.stopAdvertising()
    }
    
    private func setUpPeripheral() {
        let transferCharacteristic = CBMutableCharacteristic(type: characteristicCBUUID,
                                                             properties: [.read, .notify, .writeWithoutResponse],
                                                             value: nil,
                                                             permissions: [.readable, .writeable])
        // サービスの作成
        let transferService = CBMutableService(type: serviceCBUUID, primary: true)
        // サービスにcharacteristicsを追加
        transferService.characteristics = [transferCharacteristic]
        // periphralManagerに追加
        peripheralManager.add(transferService)
        
        self.transferCharacteristic = transferCharacteristic
        
        
        
        let data:[UInt8] = [
                             0x43,0x50,0x00,0x00,0x02,0x02,0x33,0x00,0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0x1B,0x78,0x17,0x3F,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x7F,0x00,0x00,0x00,0x32,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x27,0x08,0x00,0x00,0x02,0x00,0x04,0x7F,0x7F,0x7F,0x7F
        ]
        
        var packets = makeblepacket(rawMidi:data, tsH:0x81, tsL: 0xdf)
        
        for ap in packets {
            print(ap)
        }
        
    }
    
    static var sendingEOM = false
    
}
extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX-" : "%02hhx-"
        return self.map { String(format: format, $0) }.joined()
    }
}
import AudioToolbox
extension Data {


}
public class MIDIParser {

    public static func parse(url midiFileUrl: URL) -> ( timeline:Dictionary<Int,String> , chorduse: Dictionary<String,Int> ,
                                                        keycode: String , tempo: Double , sectionMarker:Dictionary<Int,String> ) {
        var tempo:Double = 0.0
        var chordTimeline:Dictionary<Int,String> = [:]
        var chordCounter:Dictionary<String,Int> = [:]
        var sectionMarker:Dictionary<Int,String> = [ : ]
        var keycode: String = ""
        let suffix:[String] = ["bbb", "bb" , "b" , "" , "#" , "##", "###"]
        let root_tone:[String] = [ "x" ,"C" ,"D", "E", "F" , "G" , "A" , "B"]
        let chord_type:[String] = [
          "" , "M6" , "M7" , "M7(#11)", "M(9)" , "M7(9)" ,"M6(9)" , "aug" ,
          "m" , "m6" , "m7" , "m7b5" ,"m(9)", "m7(11)", "m7(11)", "mM7" ,
          "mM7(9)", "dim" , "dim7" ,"7","7sus4","7b5","7(9)" , "7(#11)" ,
          "7(13)","7(b9)","7(b13)","7(#9)","M7aug","7aug","1+8","1+5",
          "sus4","1+2+5","cc"
        ]
        

        var musicSequence: MusicSequence?
        var result = OSStatus(noErr)
        result = NewMusicSequence(&musicSequence)
        guard let sequence = musicSequence else {
            print("error creating sequence : \(result)")
            return (chordTimeline,chordCounter,keycode,tempo,sectionMarker)
        }
        
        // MIDIファイルの読み込み
        MusicSequenceFileLoad(sequence, midiFileUrl as CFURL, .midiType, MusicSequenceLoadFlags.smf_ChannelsToTracks)
        
        var musicTrack: MusicTrack? = nil
        var sequenceLength: MusicTimeStamp = 0
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        var musicTempoTrack: MusicTrack? = nil
        MusicSequenceGetTempoTrack(sequence, &musicTempoTrack)

            var tmpIterator: MusicEventIterator?
            NewMusicEventIterator(musicTempoTrack!, &tmpIterator)
            let iterator = tmpIterator!
            
            var hasNext: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iterator, &hasNext)
            
            var type: MusicEventType = 0
            var stamp: MusicTimeStamp = -1
            var data: UnsafeRawPointer?
            var size: UInt32 = 0
            while hasNext.boolValue {
                MusicEventIteratorGetEventInfo(iterator, &stamp, &type, &data, &size)
                if type == kMusicEventType_ExtendedTempo {
                    let messagePtr = UnsafePointer<ExtendedTempoEvent>(data?.assumingMemoryBound(to: ExtendedTempoEvent.self))
                    print("tempo")
                    print(messagePtr?.pointee.bpm)
                    tempo = Double(messagePtr!.pointee.bpm)

                }
                
                
                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasNext)
            }
        for i in 0 ..< trackCount {
            var trackLength: MusicTimeStamp = 0
            var trackLengthSize: UInt32 = 0
            
            MusicSequenceGetIndTrack(sequence, i, &musicTrack)
            guard let track = musicTrack else {
                continue
            }
            
            MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &trackLengthSize)
            
            if sequenceLength < trackLength {
                sequenceLength = trackLength
            }
            
            var tmpIterator: MusicEventIterator?
            NewMusicEventIterator(track, &tmpIterator)
            guard let iterator = tmpIterator else {
                continue
            }
            
            var hasNext: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iterator, &hasNext)
            
            var type: MusicEventType = 0
            var stamp: MusicTimeStamp = -1
            var data: UnsafeRawPointer?
            var size: UInt32 = 0
            while hasNext.boolValue {
                MusicEventIteratorGetEventInfo(iterator, &stamp, &type, &data, &size)
                /*
                print( "\(stamp) - \(type) - \(size) ")
                
                var ptr = data?.bindMemory(to: UInt8.self,capacity: Int(size) )
                print(ptr?.pointee)
                for n in 0 ..< Int(size) {
                    print(ptr?[n])
                }*/
                if type == kMusicEventType_ExtendedTempo {
                    let messagePtr = UnsafePointer<ExtendedTempoEvent>(data?.assumingMemoryBound(to: ExtendedTempoEvent.self))
                    print("tempo")
                    print(messagePtr?.pointee.bpm)
                    tempo = Double(messagePtr!.pointee.bpm)

                }
                
                if type == 8 {
                    let messagePtr = UnsafePointer<MIDIRawData>(data?.assumingMemoryBound(to: MIDIRawData.self))
                    
                    /*
                    guard let channel = messagePtr?.pointee.channel,
                          let note = messagePtr?.pointee.note,
                          let velocity = messagePtr?.pointee.velocity,
                          let duration = messagePtr?.pointee.duration else {
                        continue*/
                    let dataPtr  = UnsafePointer<UInt8>(data?.assumingMemoryBound(to: UInt8.self))
                    //print(messagePtr)
                    for n in 0 ..< Int(size) {
                        //print(dataPtr?[n])
                        if( dataPtr?[n] == 0xf0 ){
//                            print("Sysex start")
                            
                            let len = Int(size) - n
                            
                            if( len == 9) {
                                if( dataPtr?[2+n] == 0x7e && dataPtr?[3+n] == 0x02){

                                    //print("Chord Data")
                                    let root = dataPtr?[4+n];
                                    let type = dataPtr?[5+n];
                                    let bass = dataPtr?[6+n];
                                    
                                    var chordname = root_tone[ (Int(root!) as Int) & 0x0f ] + suffix[ ((Int(root!) as Int)>>4)&0x0f ]
                                    if( type! == (chord_type.count - 1)  ){
                                        chordname = "NC"
                                    }else{
                                        chordname = chordname + chord_type[Int(type!)]
                                    }
                                    if( bass! & 0xff != 0x7F && root != bass ){
                                        chordname = chordname + "/" + root_tone[ Int(bass!) & 0x0f ] + suffix[ ((Int(bass!) as Int)>>4)&0x0f ]
                                    }
                                    // print( String(stamp) + " " + chordname )
                                    
                                    chordTimeline.updateValue(chordname, forKey: Int(stamp))
                                    if ( !chordCounter.keys.contains(chordname)){
                                        chordCounter.updateValue( 1, forKey: chordname)

                                    }else{
                                        chordCounter.updateValue( chordCounter[chordname]! + 1 , forKey:chordname )
                                    }
                                }
                                continue

                            }
                            
                            
                            if(dataPtr?[2+n] == 0x73 && dataPtr?[3+n] == 0x01 && dataPtr?[4+n] == 0x52 && dataPtr?[5+n]==0x2d ){
                                print("Key Data")
                                let  k=dataPtr?[6+n];
                                let  minor=dataPtr?[7+n];
                                var keycode = ""
                                let  sharpcount:[String] = [ "C" , "G" , "D","A","E","B","F#","C#" ]
                                let  flatcount:[String] = [ "C" , "F","Bb","Eb" , "Ab" , "Db","Gb" , "Cb"]
                                let  sharpcount_min:[String] = [ "Am" , "Em" , "Bm","F#m","C#m","G#m","D#m","A#m" ]
                                let  flatcount_min:[String] = [ "C" , "F","Bb","Eb" , "Ab" , "Db","Gb" , "Cb"]
                                if( k! >= 0x40 ){
                                    if( minor == 0 ){
                                        keycode = sharpcount[Int(k!)-0x40]
                                    }else{
                                        keycode = sharpcount_min[Int(k!)-0x40]
                                    }
                                }else{
                                    if( minor == 0 ){
                                        keycode = flatcount[0x40-Int(k!)]
                                    }else{
                                        keycode = flatcount_min[0x40-Int(k!)]
                                    }

                                }
                                print(keycode)
                                continue

                            }
                            
                            if(dataPtr?[2+n] == 0x7e && dataPtr?[3+n] == 0x00  ){
                                
                                print("MARKER ?? " + String(dataPtr?[4+n] ?? 0 ,radix: 16) + String(dataPtr?[5+n] ?? 0 ,radix: 16))
                                sectionMarker.updateValue( String(dataPtr?[4+n] ?? 0 ,radix: 16) , forKey: Int(stamp) )
                                continue
                            }
                            print("Uncovered Sysex")
                            for t in n ..< Int(size) {
                                print(String(  UInt8(dataPtr![t]),radix:16))
                            }
                        }
                    }
                }

                
                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasNext)
            }
            DisposeMusicEventIterator(iterator)
            MusicSequenceDisposeTrack(sequence, track)
        }
        DisposeMusicSequence(sequence)
        return (chordTimeline,chordCounter,keycode,tempo,sectionMarker)
    }
}
extension PeripheralViewModel: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print(".powerOn")
            setUpPeripheral()
            return
            
        case .poweredOff :
            print(".powerOff")
            return
            
        case .resetting:
            print(".restting")
            return
            
        case .unauthorized:
            print(".unauthorized")
            return
            
        case .unknown:
            print(".unknown")
            return
            
        case .unsupported:
            print(".unsupported")
            return
            
        default:
            print("A previously unknown central manager state occurred")
            return
        }
    }
    
    // characteristicが読み込まれたときにキャッチし、データ送信を開始
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("Central subscribed to characteristic")
        self.status="認証を待っています"

        if let message = message.data(using: .utf8) {
            dataToSend = message
        }
     
        sendDataIndex = 0
        
        connectedCentral = central
        // 送信開始
        //sendData()
    }
    
    // セントラルが停止したときに呼び出される
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("Central unsubscribed from characteristic")
        connectedCentral = nil
        self.status="切断されました"
    }
    
    
    // peripheralManagerが次のデータを送信する準備ができたときに呼び出される
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        sendData()
    }
    
    func makeblepacket(rawMidi:[UInt8],tsH:UInt8,tsL:UInt8) -> [[UInt8]]{
        if( rawMidi.count > 20 ){
            var packet:[UInt8] = [tsH]
            var packets:[[UInt8]] = []

            for x in 0..<rawMidi.count {
                if( x == 0 ){
                    packet.append(tsL)
                    packet.append(0xf0)
                }
                packet.append(rawMidi[x])
                
                if( packet.count > 16 ){
                    packets.append(packet)
                    packet = Array<UInt8>()
                    packet.append(tsH)
                }
            }
            packet.append(tsL)
            packet.append(0xf7)
            packets.append(packet)
            return packets
        }else{
            var packet = [ tsH , tsL ]
            packet.append(contentsOf: rawMidi)
            return [packet]
        }
        
    }
    
    func addSendQueue(data:[UInt8]){
        let d = Data(bytes: data)
        sendQ.append(d)
        sendData()
    }
    
    func sendData(){
        while(!sendQ.isEmpty){
            print(sendQ.count)
            let d=sendQ[0]
            self.transferCharacteristic?.value = d
            if( peripheralManager.updateValue( d, for: self.transferCharacteristic!, onSubscribedCentrals: nil) == false ){
                print("send failed")
                break
            }else{
                sendQ.popFirst()
                print("send succeed --->")
                print(d.hexEncodedString())
                print("<----")
            }
        }
    }

    func createFile(atPath path: String, contents: Data?) {
        
        var midi:[UInt8] = []
        var t=Data(recvFile)
        print(t.hexEncodedString())
        
        // Documentsディレクトリまでのパスを生成
        guard let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else{
            fatalError("URL取得失敗")
        }
        // ファイル名を含めたフルパスを生成
        let fullURL = docURL.appendingPathComponent(path)
        
        do {
            // 書き込み処理
            try t.write(to:fullURL)
        } catch{
            print("書き込み失敗")
        }
        
        var mp = MIDIParser.parse(url: fullURL)
        var lastchord = "NC"
        var newline:Bool = false
        chords = fullURL.lastPathComponent
        chords = chords + "\n Tempo : \(mp.3) "
        var sectionbeats:Int = 0
        for time in 0 ..< mp.0.keys.sorted().last! {
            var line = " "
            
            if( mp.sectionMarker.keys.contains(time)){
                sectionbeats = time
                chords = chords + " \n "
                newline = true
            }
            if( mp.timeline.keys.contains(time) ){
                line = line +  mp.timeline[time]!
                newline=false
                lastchord = mp.timeline[time]!
            }else{
                if( newline ){
                    line = line + lastchord + " "
                }else{
                    line = line + " "
                }
                
            }
            if( ((time - sectionbeats) % 4) == 3 ){
                line = line + " | "
            }

            
//            print(line)
            chords = chords + line
        }
        /*
        for n in 0 ..< mp.0.count {
            var t = mp.0.keys.sorted()[n]
            print( "\(t) - \(mp.0[t]!)" )
        }*/
    }
    
    
    func decode7bitto8(data:[UInt8]) -> [UInt8]{
        var q:Deque<UInt8> = []
        var outs:[UInt8] = []
        q.append(contentsOf: data)
        while(!q.isEmpty){
            var flags=q.popFirst()!
            flags = flags << 1
            for x in 0 ..< 7 {
                if( q.isEmpty ) { break }
                outs.append((flags & 0x80) |  q.popFirst()!)
                flags = flags << 1
            }
        }
        return outs
    }
    
    
    func parseData(){

        while(!recvQ.isEmpty ){
  //          print("--read tsL---")

            var tsL=recvQ.popFirst()
            var msg:Deque<UInt8?> = []
            var c:UInt8? = recvQ.popFirst() as? UInt8
  //          print("--read first---")
            
            print( String(c!,radix:16))
            if( c == 0xf0 ){
                // sysex
                msg.append(c)
                
                while(!recvQ.isEmpty){
//                    print("--read body---")
                    let s:UInt8? = recvQ.popFirst()
                    msg.append(s)
                    //print( String(s!,radix:16))

                    if( (s! & 0x80) == 0  ){
                        // surely data body

                    }else{
                        // tsL or eox ??
                        if( s == 0xf7 ){
    //                        print("read f7")
                            if( !recvQ.isEmpty ){
                                let s2 = recvQ[0]
                                if( s2 == 0xf7 ){
      //                              print( "catch next f7")
                                    msg.append(recvQ.popFirst())
        //                            print("eox2")
                                    messages.append(msg)
                                    break
                                }else{
                                    messages.append(msg)
          //                          print("eox")
                                    break

                                }
                            }else{
                                // surely eox
            //                    print("eox1")
                                messages.append(msg)
                                break
                            }
                        }else{
                            
                            // this is timestamp low
                            
                        }

                    }
                }
            } else {
                //
                // unexpected splitted msg
            }
            //print("next data")
        }
        print("anaPacket")
        while(!messages.isEmpty){
            var d = messages.popFirst()
            print(String(d!.count) + "bytes message")
            var data:[UInt8] = Array<UInt8>()
            
            //var msdc = isMSDCtlMessage(d: d?._copyToContiguousArray() )

            if( d?.count == 7 ){
                if( d?[3] == 0x06 && d?[4] == 0x01 ){
                    print("ID Request")
                    
                    // SHS-300
                    /*
                    let data:[UInt8] = [ 0x81 , 0xcf ,
                                 0xF0,0x7E,0x7F,0x06,0x02,0x43,0x00,0x44,0x2E,0x1F,0x00,0x00,0x00,0x7F,0xcf,0xF7
                    ]*/
                    
                    let data:[UInt8] = [ 0x81 , 0xcf ,
                                 0xF0,0x7E,0x7F,0x06,0x02,0x43,0x00,0x44,0x42,0x1C,0x0A,0x00,0x00,0x1,0xcf,0xF7
                    ]
                    
                    addSendQueue(data: data)
                    self.status="ID送信中"

                }
            }
            if( d?.count == 9 ){
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                    if( d?[3] == 0x00 && d?[4] == 0x00 && d?[5] == 0x00 ){
                        if( d?[6] == 1 ){
                            print("Is MSD Mode supported query")
                            
                            // F0 43 50 00 00 00 02 01 01 F7
                            let data:[UInt8] = [ 0x81 , 0xdf ,
                                                 
                                                 0xF0,0x43,0x50,0x00,0x00,0x00,0x02, 0x01 , 0x1 ,0xdf ,0xF7
                            ]
                            addSendQueue(data: data)
                        }
                            
                    }
                }
            }
            
//            F0 43 50 00 00 01 01 F7
//                Genos responds:         F0 43 50 00 00 01 02 00 F7
            // 80-80-f0-43-50-00-00-01-01-80-f7")
            if( d?.count == 9){
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                    if( d?[3] == 0x00 && d?[4] == 0x00 && d?[5] == 0x01 && d?[6] == 0x01){
                        print( "MSD Mode on request" )
                        // F0 43 50 00 00 00 02 01 01 F7
                        let data:[UInt8] = [ 0x81 , 0xdf ,
                                             
                                             0xF0,0x43,0x50,0x00,0x00,0x01,0x02, 0x00 ,0xdf ,0xF7
                        ]
                        addSendQueue(data: data)
                    }
                }
            }
            if( d?.count == 10){
                //a7-fc-f0-43-50-00-05-0b-00-00-fc-f7
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                    if( d?[3] == 0x00 && d?[4] == 0x05 && d?[5] == 0x0b ){
                        print( "Request driver 0 info" )
                        let data:[UInt8] = [ 0x81 , 0xdf ,
                                             
                                             0xF0,0x43,0x50,0x00,0x05,0x0B,0x01,0x42,
                                             0x00,0x00,0x05,0x00,0x55,0x53,0x45,0x52 ,0xdf ,0xF7
                        ]
                        
                        addSendQueue(data: data)
                        isReceiveMidi = true

                    }
                }
            }
            if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                if( d?[3] == 0x00 && d?[4] == 0x05 && (d?[5] == 0x06) ){
                    // meminfo ??
                    print("meminfo")
                    let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x05,0x06,0x01,0x02,0x7f,0x7f,0x7f,0x7f,0xdf,0xf7 ]
                    addSendQueue(data: data)
                    
                }
            }

            
            // ("f0-43-50-00- 06-01-00-
            // 05-00-00-00-16-20-   filesize
            // 05-00-00-00-00-00-
            // 00-20-                                                         　83    83 89       83 62
            // 0f-　30-3a-5c-10-62-11-4e-   40-　13-49-65-6e-65-72-67-　3b-　79-01-19-03-4c-03-09-  40- 03-62-2e- 6d- 69-64- 00- c1-f7-")
            //           0  : ¥      b       N   @     I  e  n e   r g     　y　　キ　　　　ラ　　　 　 　ツ
            if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                if( d?[3] == 0x00 && d?[4] == 0x06 && (d?[5] == 0x01) ){
                    print("06 message !!")
                    let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x03,0x00,0x01,0xdf,0xf7 ]
                    
                    addSendQueue(data: data)
                    var fsdata:[UInt8]=[ d![10]!,d![11]!,d![12]!,d![13]! ]
                    
                    var fname:[UInt8] = []
                    for n in 21 ..< d!.count-2 {
                        fname.append(d![n]!)
                    }
                    
                    var filename = decode7bitto8(data: fname)
                    while(filename.last == 0){
                        filename=filename.dropLast()
                    }
                    // drop 0:¥¥
                    filename.removeFirst(3)
                    
                    savemidifilename = (String(bytes: filename, encoding: .shiftJIS))!
                    receiveMessage = receiveMessage + "\n" + "ファイル名：" + savemidifilename
                    
                    
/*
                        var b1:UInt8 = filesize.next(bits: 7).uint8
                        var b2:UInt8 = filesize.next(bits: 7).uint8
                        var b3:UInt8 = filesize.next(bits: 7).uint8
                        var b4:UInt8 = filesize.next(bits: 7).uint8
                        
 
 
  */
                recvFile = Deque<UInt8>()
                    
                }
            }
            if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                if( d?[3] == 0x01 && ( d?[4] == 0x01 || d?[4] == 0x00 )  ){
                        print("file packet")
                    var tmp:[UInt8] = []
                        for n in 9 ..< d!.count-2  {
                            tmp.append(UInt8(d![n]!))
                        }
                    var q:Deque<UInt8> = []
                    q.append(contentsOf: tmp)
                    print(Data(tmp).hexEncodedString())
                    while(!q.isEmpty){
                        var flags=q.popFirst()!
                        flags = flags << 1
                        for x in 0 ..< 7 {
                            if( q.isEmpty ) { break }
                            recvFile.append( (flags & 0x80) |  q.popFirst()!)
                            flags = flags << 1
                        }
                    }
                        
                    if( d?[4] == 0x00 ){
                        // EOF
                        let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x03,0x00,0x00,0xdf,0xf7 ]
                        addSendQueue(data: data)

                    }else{
                        let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x03,0x00,0x01,0xdf,0xf7 ]
                        addSendQueue(data: data)

                    }
                    progressReceiveMidi = "\(recvFile.count)バイト"

                }
            }
            // 97-f1-f0-43-50-00-03-02-f1-f7-
            if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                if( d?[3] == 0x00 &&  d?[4] == 0x03  && d?[5] == 0x02 ){
//                    let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x03,0x00,0x01,0xdf,0xf7 ]
//                    addSendQueue(data: [0xa7,0xfc,0xF0,0x43,0x50,0x00,0x05,0x7F,0x01,0x01,0x01,0x42,0x00,0x00,0xfc,0xF7])
//                    let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x03,0x00,0x01,0xdf,0xf7 ]
//                    addSendQueue(data: data)
                    let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50,0x00,0x03,0x03,0xdf,0xf7 ]
                    addSendQueue(data: data)
                    

                    createFile(atPath: savemidifilename , contents: Data(recvFile) )
                    
                    recvFile = []

                    midiComplete = true
                    isReceiveMidi = false
                    
                    
                }
            }
            
            // a9-f3-f0-43-50-00-05-00-00-00-00-18-00-30
            if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                if( d?[3] == 0x00 && d?[4] == 0x05 && (d?[5] == 0x00) ){
                    // meminfo ??
                    print("makedir")
                    let data:[UInt8] = [ 0x81,0xdf , 0xf0,0x43,0x50 ,0x00,0x05,0x00 ,0x01 , 0x00 , 0xdf,0xf7 ]
                    addSendQueue(data: data)
                    
                }
            }

            //
            //80-8d-f0-43-50-00-05-06-00-00-8d-f7-
                //a7-fc-f0-43-50-00-05-0b-00-00-fc-f7
            if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                if( d?[3] == 0x00 && d?[4] == 0x05 && (d?[5] == 0x05 || d?[5] == 0x04) ){
                    print( "command[5-(5-4)] : file list request" )
                    
                    if( d?[5] == 0x04 ){
                        print("FindFirst")
                        filelistcount = 0
                    }
                    switch(filelistcount){
                        case 0:
                            let data:[UInt8] = [ 0x43,0x50,0x00,0x05,0x04,0x01,0x10,0x31,0x39,0x38,0x30,0x20,0x31,0x20,0x31,0x20,0x30,0x20,0x30,0x20,0x30,0x03,0x01,0x00,0x00,0x00,0x03,0x00,0x2E,0x00 ]
                            let d=makeblepacket(rawMidi: data, tsH: 0xa7, tsL: 0xfc)
                            for ad in d {
                                addSendQueue(data: ad)
                            }
                            break
                        case 1:
                            let data2:[UInt8] = [0x43,0x50,0x00,0x05,0x05,0x01,0x10,0x32,0x30,0x32,0x31,0x20,0x36,0x32,0x36,0x20,0x30,0x34,0x34,0x35,0x34,0x03,0x01,0x00,0x00,0x00,0x06,0x00,0x53,0x4F,0x4E,0x47,0x00,0x00 ]
                            let d=makeblepacket(rawMidi: data2, tsH: 0xa7, tsL: 0xfc)
                            for ad in d {
                                addSendQueue(data: ad)
                            }
                            break
                        case 2:
                            let data2:[UInt8] = [0x43,0x50,0x00,0x05,0x05,0x01,0x10,0x32,0x30,0x32,0x31,0x20,0x36,0x32,0x36,0x20,0x30,0x34,0x34,0x35,0x34,0x03,0x01,0x00,0x00,0x00,0x06,0x00,0x53,0x4F,0x4E,0x47,0x00,0x00 ]
                            let d=makeblepacket(rawMidi: data2, tsH: 0xa7, tsL: 0xfc)
                            for ad in d {
                                addSendQueue(data: ad)
                            }
                            break

                    default:
                            addSendQueue(data: [0xa7,0xfc,0xF0,0x43,0x50,0x00,0x05,0x7F,0x01,0x01,0x01,0x42,0x00,0x00,0xfc,0xF7])
                            break
                    }
                    filelistcount = filelistcount + 1
                }
                
            }
	
            if( d?.count == 10 ){
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                    if( d?[3] == 0x00 && d?[4] == 0x00 && d?[5] == 0x01 && d?[6] == 0x00 && d?[7] == 0x01){
                        print( "connect/disconnect message" )
                        // F0 43 50 00 00 01 02 01 F7
                        let data:[UInt8] = [ 0x81 , 0xdf ,
                                             
                                             0xF0,0x43,0x50,0x00,0x00	,0x01, 0x02 , 0x01 , 0xdf ,0xF7
                        ]

                        addSendQueue(data: data)
                    }
                }
            }
            // 97-ef-f0-43-50-00-05-04-00-3f-00-08-00-30-3a-5c-2a-2e-2a-00-ef-f7
            if( d?.count == 20 ){
                // F0 43 50 00 05 04 01 10 31 39 38 30 20 31 20 31 20 30 20 30 20 30 03 01 00 00 00 03 00 2E 00 F7
                
                if (filelistcount == 0 ){
                    let data:[UInt8] = [ 0x81 , 0xdf ,
                                         
                                         0xF0,0x43,0x50,0x00,0x05,0x04,0x01,0x10,0x31,0x39,0x38,0x30,0x20,0x31,0x20,0x31
                    ]

                    addSendQueue(data: data)
                    let data2:[UInt8] = [ 0x81 ,0x20,0x30,0x20,0x30,0x20,0x30,0x03,0x01,0x00,0x00,0x00,0x03,0x00,0x2E,0x00,0xF7
                                         
                                         , 0xdf ,0xF7
                    ]


                    addSendQueue(data: data2)
                }
                

                filelistcount = filelistcount + 1
            }
            
            if( d?.count == 9){
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                    if( d?[3] == 0x00 && d?[4] == 0x00 && d?[5] == 0x02 && d?[6] == 0x01){
                        print( "SupportInfo" )
                        
                        let data:[UInt8] = [
                                             0x43,0x50,0x00,0x00,0x02,0x02,0x33,0x00,0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0x1B,0x78,0x17,0x3F,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x7F,0x00,0x00,0x00,0x32,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x27,0x08,0x00,0x00,0x02,0x00,0x04,0x7F,0x7F,0x7F,0x7F
                        ]
                        
                        var packets = makeblepacket(rawMidi:data, tsH:0x81, tsL: 0xdf)
                        
                        for ap in packets {
                            print(ap)
                            addSendQueue(data: ap)
                        }
                        
                        
                    }
                }
            }
            if( d?.count == 9 ){
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x50 ){
                    if( d?[3] == 0x00 && d?[4] == 0x00 && d?[5] == 0x07 ){
                        print("name query.")
                        let data:[UInt8] = [ 0x81 , 0xdf ,
                        
                                     0xF0,0x43,0x50,0x00,0x00,0x07,0x02, 0x0A , 0x00, 0x53,0x48,0x53,0x2D,0x33,0x30,0x30 ,0x00,0x00, 0xdf ,0xF7
                        ]
                        
                        addSendQueue(data: data)
                        self.status="機種名送信中"
                    }
                }
            }

            if( d?.count == 11 ){
                if( d?[0] == 0xf0 && d?[1] == 0x43 && d?[2] == 0x73 ){
                    if( d?[3] == 0x1 && d?[4] == 0x52 && d?[5] == 0x25 && d?[6] == 0x28 ){
                        print("Spec query.")
                        
                        
                        let data1:[UInt8] = [ 0x81 , 0xd0 ,
                        
                                             0xF0 ,0x43 , 0x73 ,0x01 ,0x52 , 0x25 , 0x28, 0x01 ,0x01 ,0xd0 ,0xF7
                        ]

                        let data2:[UInt8] = [ 0x81 , 0xd1 ,
                        
                                             0xF0 ,0x43 , 0x73 ,0x01 ,0x52 , 0x25 , 0x28, 0x02 ,0x00 , 0xd1 ,0xF7
                        ]

                        let data3:[UInt8] = [ 0x81 , 0xd2 ,
                        
                                             0xF0 ,0x43 , 0x73 ,0x01 ,0x52 , 0x25 , 0x28, 0x03 ,0x01 , 0xd2 ,0xF7
                        ]

                        addSendQueue(data: data1)
                        
                        /*
                        addSendQueue(data: data2)
                        
                        addSendQueue(data: data3)*/
                        self.status="スペック送信完了"
                        self.status="接続完了"

                        
                    }
                }
            }
            
            let suffix:[String] = ["bbb", "bb" , "b" , "" , "#" , "##", "###"]
            let root_tone:[String] = [ "x" ,"C" ,"D", "E", "F" , "G" , "A" , "B"]
            let chord_type:[String] = [
              "" , "M6" , "M7" , "M7(#11)", "M(9)" , "M7(9)" ,"M6(9)" , "aug" ,
              "m" , "m6" , "m7" , "m7b5" ,"m(9)", "m7(11)", "m7(11)", "mM7" ,
              "mM7(9)", "dim" , "dim7" ,"7","7sus4","7b5","7(9)" , "7(#11)" ,
              "7(13)","7(b9)","7(b13)","7(#9)","M7aug","7aug","1+8","1+5",
              "sus4","1+2+5","cc"
            ]
            
            if( d?.count == 10 ){
                // xx-f0-43-7e-02-37-0a-7f-7f-xx-f7-")
                if( d?[0] == 0xf0 && d?[1]==0x43 && d?[2] == 0x7e && d?[3] == 0x02 ){
                    print("Chord Data")
                    let root = d?[4];
                    let type = d?[5];
                    let bass = d?[6];
                    
                    var chordname = root_tone[ (Int(root!) as Int) & 0x0f ] + suffix[ ((Int(root!) as Int)>>4)&0x0f ]
                    if( type! == (chord_type.count - 1)  ){
                        chordname = "NC"
                    }else{
                        chordname = chordname + chord_type[Int(type!)]
                    }
                    if( bass! & 0xff != 0x7F){
                        chordname = chordname + "/" + root_tone[ Int(bass!) & 0x0f ] + suffix[ ((Int(bass!) as Int)>>4)&0x0f ]
                    }
                    print(chordname)
                    lastCord=chordname
                    chords = chords + " "  + chordname
                    status="コード受信"
                }

                
                // F0  43  73  1  52  2D  44  1  F7
                if( d?[0] == 0xf0 && d?[1]==0x43 && d?[2] == 0x73 && d?[3] == 0x01 && d?[4] == 0x52 && d?[5]==0x2d ){
                    print("Key Data")
                    let  k=d?[6];
                    let  minor=d?[7];
                    
                    let  sharpcount:[String] = [ "C" , "G" , "D","A","E","B","F#","C#" ]
                    let  flatcount:[String] = [ "C" , "F","Bb","Eb" , "Ab" , "Db","Gb" , "Cb"]
                    let  sharpcount_min:[String] = [ "Am" , "Em" , "Bm","F#m","C#m","G#m","D#m","A#m" ]
                    let  flatcount_min:[String] = [ "C" , "F","Bb","Eb" , "Ab" , "Db","Gb" , "Cb"]
                    if( k! >= 0x40 ){
                        if( minor == 0 ){
                            keycode = sharpcount[Int(k!)-0x40]
                        }else{
                            keycode = sharpcount_min[Int(k!)-0x40]
                        }
                    }else{
                        if( minor == 0 ){
                            keycode = flatcount[0x40-Int(k!)]
                        }else{
                            keycode = flatcount_min[0x40-Int(k!)]
                        }

                    }
                    print(keycode)
                    status="調性受信"
                }

            }
        }
        
        /*
        if( aRequest.value?.count == 9 ){
            if( aRequest.value?[2] == 0xf0 && aRequest.value?[3] == 0x7e && aRequest.value?[4] == 0x7f ){
                if( aRequest.value?[5]==0x06 && aRequest.value?[6]==0x01){
                    print("ID Request Recv.")

                    print("response ID" )
                }
            }

            if( aRequest.value?[2] == 0xf0 && aRequest.value?[3] == 0x43 && aRequest.value?[4] == 0x50 ){
                if( aRequest.value?[5] == 0x00 && aRequest.value?[6] == 0x00 && aRequest.value?[7] == 0x07 ){
                    print("name query.")
                    let data:[UInt8] = [ aRequest.value![0] , aRequest.value![1] ,
                    
                                 0xF0,0x43,0x50,0x00,0x00,0x07,0x02, 0x0A , 0x00, 0x53,0x48,0x53,0x2D,0x33,0x30,0x30 ,0x00,0x00,aRequest.value![1],0xF7
                    
                    ]
                    
                    let d = Data(bytes: data)
                    self.transferCharacteristic?.value = d
                    peripheralManager.updateValue( d, for: self.transferCharacteristic!, onSubscribedCentrals: nil)
                    print("response ID" )
                }
            }

            
        }*/
        

    }
    // peripheralManagerがcharacteristicsへの書き込みを受信したときに呼び出される
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            
            /*
            guard let requestValue = aRequest.value,
                  let stringFromData = String(data: requestValue, encoding: .utf8) else {
                continue
            }
            
            print("Received write request of \(requestValue.count) bytes: \(stringFromData)")
            message = stringFromData
            */
            print ("write value from external ")
            print( aRequest.value?.hexEncodedString() )
            self.transferCharacteristic?.value = aRequest.value

            var lastData:UInt8=0
            for n in 0 ..< aRequest.value!.count {
                if( flagSplit && n == 0 ){
                    continue //
                }
                if( !flagSplit && n == 1){
                    continue
                }
                
                recvQ.append(aRequest.value![n])

                
                if( flagSplit && n == (aRequest.value!.count-1) && aRequest.value![n] == 0xf7 ){
                    flagSplit = false
                }
                lastData = aRequest.value![n]
            }
            
  //          print("diff=" + String(diff))
            if( lastData == 0xf7 ){
                parseData()
            }else{
                print("splitted packet..")
                flagSplit = true

            }
            

            
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest){
        /*
        if (request.characteristic.uuid.isEqual(self.characteristic.uuid)) {
            if let value = self.characteristic.value{
                if (request.offset > value.count) {
                    peripheral.respond(to: request, withResult: CBATTError.invalidOffset)
                    print("Read fail: invalid offset")
                    return;
                }
            }

            request.value = self.characteristic.value?.subdata(
                in: Range(uncheckedBounds: (request.offset, (self.characteristic.value?.count)! - request.offset))
            )
            peripheral.respond(to: request, withResult: CBATTError.success)
            print("Read success")
        }else{
            print("Read fail: wrong characteristic uuid:", request.characteristic.uuid)
        }*/
            
            /*
            guard let requestValue = aRequest.value,
                  let stringFromData = String(data: requestValue, encoding: .utf8) else {
                continue
            }
            
            print("Received write request of \(requestValue.count) bytes: \(stringFromData)")
            message = stringFromData
            */
        print ("read")
        
        print("Received read request: MTU")
              print(request.central.maximumUpdateValueLength);

            print( request.characteristic.uuid.uuidString  )
        transferCharacteristic?.value = request.value
            peripheral.respond(to: request , withResult: .success)
            //print( request.value?.hexEncodedString() )
                
    }
}

// コピーしました用のメッセージバルーン
class MessageBalloon:ObservableObject{
    
// opacityモディファイアの引数に使用
    @Published  var opacity:Double = 10.0
// 表示/非表示を切り替える用
    @Published  var isPreview:Bool = false
    
    private var timer = Timer()
    
    // Double型にキャスト＆opacityモディファイア用の数値に割り算
    func castOpacity() -> Double{
        Double(self.opacity / 10)
    }
    
    // opacityを徐々に減らすことでアニメーションを実装
    func vanishMessage(){
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true){ _ in
            self.opacity = self.opacity - 1.0 // デクリメント
            
            if(self.opacity == 0.0){
                self.isPreview = false  // 非表示
                self.opacity = 10.0     // 初期値リセット
                self.timer.invalidate() // タイマーストップ
            }
        }
    }
    
}
struct PeripheralView: View {
    @Namespace var topID
    @Namespace var bottomID
    @StateObject var peripheral: PeripheralViewModel = PeripheralViewModel()
    @State var copymsg:Bool = false
    @State var toScroll:Int = 0

    var body: some View {
        
        VStack {
            HStack{
                Text("CT Receiver").font(.custom("Superclarendon-Bold", size: 24)).foregroundColor(.white)
                    .shadow(color:Color.gray,radius: 3,x:3,y:3).padding(1)
                    .background(Color.black).border(/*@START_MENU_TOKEN@*/Color.black/*@END_MENU_TOKEN@*/)
                ZStack{
                    Text(peripheral.keycode).font(.title).foregroundColor(.white).frame(width:60,height:32)
                        .shadow(color:Color.gray,radius: 3,x:3,y:3).padding(5)
                        .background(Color.green).border(Color.gray,width: 3)
                    Text("Key").foregroundColor(.gray).frame(width:60,height:32)
                        .shadow(color:Color.gray,radius: 3,x:3,y:3).padding(5)
                        .background(Color.green).border(Color.gray,width: 3)
                        .opacity((peripheral.keycode=="---") ? 1 : 0)
                }
                Spacer()
                Button(action: {
                    peripheral.chords = ""
                }){
                    Text("Clear") .fontWeight(.semibold)
                        .frame(width: 64, height: 32)
                        .foregroundColor(Color(.black))
                        .background(Color.red)
                        .cornerRadius(24).shadow(color:Color.gray,radius: 3,x:3,y:3)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack{
                        let  ver =  Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
                        
                        VStack{
                            Text("\n").id(topID)
                            Text(peripheral.chords)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity)/*.border(Color.blue)*/
                            Text("\n").id(bottomID)
                        }
                        let startupMessage = "System Ver : " + ver + "\n" + "BLE待受をONにしてください"
                        Text(startupMessage).opacity(peripheral.toggleFrag ? 0 : 1)
                        VStack{
                            Text("\(peripheral.receiveMessage)")
                            Text("\(peripheral.progressReceiveMidi)")
                        }.alert(isPresented:$peripheral.midiComplete){
                            Alert(title: Text(""),
                                  message: Text("MIDIファイル[\(peripheral.savemidifilename)] 受信完了"),
                                  dismissButton: .default(Text("了解"))
                             )
                        }.foregroundColor(Color.white).background(Color.blue).opacity( peripheral.isReceiveMidi ? 1 : 0)
                                    
                    }
                }.onChange(of: toScroll) { _ in
                    proxy.scrollTo(bottomID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 300)
            .background(Color.green)
            .border(Color.gray,width: 8)
            .cornerRadius(12)
            HStack {
                Button(action: {
                    peripheral.chords = peripheral.chords + " " + peripheral.lastCord
                }){
                    Text("直近コード挿入") .fontWeight(.semibold)
                        .frame(width: 160, height: 48)
                        .foregroundColor(Color(.white))
                        .background(Color(.blue))
                        .cornerRadius(12).shadow(color:Color.gray,radius: 3,x:3,y:3)
                }
                    Spacer()

                Button(action: {
                    peripheral.chords = peripheral.chords + "\n"
                    toScroll = toScroll + 1
                }){
                    Text("改行挿入") .fontWeight(.semibold)
                        .frame(width: 160, height: 48)
                        .foregroundColor(Color(.white))
                        .background(Color(.blue))
                        .cornerRadius(12).shadow(color:Color.gray,radius: 3,x:3,y:3)
                }
            }
            Spacer()
            HStack {
                Button(action: {
                    peripheral.chords = peripheral.chords + "\n" +  "--- MEMO[1] ---" + "\n"
                }){
                    Text("--- MEMO[1] ---") .fontWeight(.semibold)
                        .frame(width: 160, height: 48)
                        .foregroundColor(Color(.white))
                        .background(Color(.blue))
                        .cornerRadius(12).shadow(color:Color.gray,radius: 3,x:3,y:3)
                }
                    Spacer()

                Button(action: {
                    peripheral.chords = peripheral.chords +  "\n" +  "--- MEMO[2] ---" + "\n"
                    toScroll = toScroll + 1
                }){
                    Text("--- MEMO[2] ---") .fontWeight(.semibold)
                        .frame(width: 160, height: 48)
                        .foregroundColor(Color(.white))
                        .background(Color(.blue))
                        .cornerRadius(12).shadow(color:Color.gray,radius: 3,x:3,y:3)
                }
            }
            Spacer()
            HStack {
                Spacer()
                ZStack{

                    Button(action: {
                        UIPasteboard.general.string = peripheral.chords
                        copymsg=true
                    }){
                        Text("全文コピー") .fontWeight(.semibold)
                            .frame(width: 160, height: 40)
                            .foregroundColor(Color(.white))
                            .background(Color(.blue))
                            .cornerRadius(12).shadow(color:Color.gray,radius: 3,x:3,y:3)
                    }.alert(isPresented: $copymsg) {
                        Alert(title: Text(""),
                              message: Text("コピーしました"),
                              dismissButton: .default(Text("了解")))  // ボタンの変更
                    }
                }
            }
            HStack{
                Toggle("BLE待受", isOn: $peripheral.toggleFrag).foregroundColor(Color.white)
                    .onChange(of: peripheral.toggleFrag) { _ in
                        peripheral.switchChanged()
                    }.padding(10)
            }.background(Color.gray)
            Text(" "+peripheral.status).frame(minWidth: 300, minHeight: 20)
                .background(Color.green).shadow(color:Color.gray,radius: 3,x:3,y:3)
            
        }
    .onDisappear {
        peripheral.stopAction()
        }
    }
}
struct ContentView: View {
    var body: some View {
        
        VStack {
            /*
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")*/
            PeripheralView().background(Image("bg").resizable().scaledToFill())
        }
        
    }
}

#Preview {
    ContentView()
}
