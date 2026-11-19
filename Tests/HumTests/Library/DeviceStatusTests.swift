import Foundation
import HumCore
@testable import HumSources
@testable import HumUI
import Testing

@Suite("Playing on another device")
struct DeviceStatusTests {
    let mac = PlaybackDevice(id: "mac", name: "Studio Mac", kind: .computer, isActive: true, isThisMac: true)
    let kitchen = PlaybackDevice(id: "kitchen", name: "Kitchen", kind: .speaker, isActive: false)

    @Test func saysNothingWhileThisMacPlays() {
        #expect(DeviceStatus.resolve(devices: [mac, kitchen], connectingTo: nil) == nil)
    }

    @Test func namesTheOtherDevicePlaying() throws {
        var mac = mac
        mac.isActive = false
        var kitchen = kitchen
        kitchen.isActive = true
        let status = try #require(DeviceStatus.resolve(devices: [mac, kitchen], connectingTo: nil))
        #expect(status.phase == .playing)
        #expect(status.title == "Playing on Kitchen")
    }

    @Test func aMoveUnderWaySaysWhereItsGoing() throws {
        let status = try #require(DeviceStatus.resolve(devices: [mac, kitchen], connectingTo: "kitchen"))
        #expect(status.phase == .connecting)
        #expect(status.title == "Connecting to Kitchen…")
    }

    @Test func movingBackHereSaysNothing() {
        var mac = mac
        mac.isActive = false
        var kitchen = kitchen
        kitchen.isActive = true
        #expect(DeviceStatus.resolve(devices: [mac, kitchen], connectingTo: "mac") == nil)
    }

    @Test func nothingPlayingAnywhereSaysNothing() {
        var mac = mac
        mac.isActive = false
        #expect(DeviceStatus.resolve(devices: [mac, kitchen], connectingTo: nil) == nil)
        #expect(DeviceStatus.resolve(devices: [], connectingTo: "kitchen") == nil)
    }

    @Test func theDemoCanStartOnKitchen() {
        let options = LaunchOptions(arguments: ["hum", "--demo-device", "kitchen"], environment: [:])
        #expect(options.demo)
        #expect(options.demoDevice == "kitchen")
        #expect(LaunchOptions(arguments: ["hum", "--demo"], environment: [:]).demoDevice == nil)
    }

    @Test func theVolumeHUDSpeaksAPercentage() {
        #expect(VolumeHUD.spokenValue(0.4) == "40 percent")
        #expect(VolumeHUD.spokenValue(1.2) == "100 percent")
        #expect(VolumeHUD.spokenValue(-1) == "0 percent")
    }
}

@MainActor
@Suite("Device status in the library")
struct LibraryDeviceStatusTests {
    let clock = TestClock()

    func make(playingOn device: String? = nil) -> (LibraryStore, NowPlayingStore) {
        let clock = clock
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        let library = DemoLibrary(source: source, playingOn: device, listLatency: .zero, transferLatency: .zero)
        let nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: .demo, now: { clock.now })
        let store = LibraryStore(
            nowPlaying: nowPlaying,
            providers: [library],
            now: { clock.now },
            sleep: { _ in }
        )
        return (store, nowPlaying)
    }

    @Test func theDemoPlaysHereByDefault() async {
        let (store, _) = make()
        store.loadDevices()
        await waitUntil { store.devices.phase == .loaded }
        #expect(store.deviceStatus == nil)
    }

    @Test func theDemoStartedOnKitchenSaysSo() async {
        let (store, _) = make(playingOn: "kitchen")
        store.loadDevices()
        await waitUntil { store.devices.phase == .loaded }
        #expect(store.deviceStatus?.title == "Playing on Kitchen")
        #expect(store.deviceStatus?.device.kind == .speaker)
    }

    @Test func movingSaysConnectingThenPlaying() async throws {
        let (store, _) = make()
        store.loadDevices()
        await waitUntil { store.devices.phase == .loaded }
        let tv = try #require(store.devices.value?.first { $0.name == "Living Room TV" })
        store.transfer(to: tv)
        #expect(store.deviceStatus?.title == "Connecting to Living Room TV…")
        await waitUntil { store.transferringDeviceID == nil && store.devices.phase == .loaded }
        #expect(store.deviceStatus?.title == "Playing on Living Room TV")
    }

    @Test func whatPlaysChangingChecksTheDevicesAgain() async {
        let (store, nowPlaying) = make(playingOn: "kitchen")
        nowPlaying.start()
        await drainMainActor()
        await nowPlaying.perform(.play)
        await waitUntil { store.devices.phase == .loaded }
        #expect(store.deviceStatus?.title == "Playing on Kitchen")
    }

    @Test func anUnknownDeviceNameStartsHere() async {
        let (store, _) = make(playingOn: "garage")
        store.loadDevices()
        await waitUntil { store.devices.phase == .loaded }
        #expect(store.deviceStatus == nil)
    }
}

@MainActor
@Suite("Spotify's devices")
struct SpotifyDeviceTests {
    /// Spotify's app doesn't tell other apps where it's playing, so there's no
    /// device picker or status line for it (DESIGN.md §5.8).
    @Test func spotifyHasNoDevicesToShow() async {
        let spotify = SpotifyFixture()
        #expect(spotify.library.sourceID == .spotifyApp)
        #expect(spotify.library.capabilities.isDisjoint(with: [.devices, .deviceSwitching]))
        spotify.library.loadDevices()
        await drainMainActor()
        #expect(spotify.library.devices.value == nil)
        #expect(spotify.library.deviceStatus == nil)
        #expect(spotify.source.performed.isEmpty)
        #expect(spotify.source.playedSongs.isEmpty)
    }
}
