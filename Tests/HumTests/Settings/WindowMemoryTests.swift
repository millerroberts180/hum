import Foundation
import HumCore
import Testing

@Suite("Window memory")
struct WindowMemoryTests {
    /// What a build from before per-style sizes wrote.
    let oldJSON = """
    {
      "placements": {
        "display-a": { "offsetX": 1200, "offsetY": 600, "side": 280, "surface": "find" }
      },
      "lastDisplay": "display-a",
      "lastSurface": "find"
    }
    """

    @Test func memoryFromBeforePerStyleSizesStillLoads() throws {
        let memory = try JSONDecoder().decode(WindowMemory.self, from: Data(oldJSON.utf8))
        // Find was removed; a player remembered there opens on Now, unpinned
        // until it's placed (pins came later).
        #expect(memory.placements["display-a"] == WindowPlacement(offsetX: 1200, offsetY: 600, side: 280, surface: .now))
        #expect(memory.placements["display-a"]?.pin == nil)
        #expect(memory.lastDisplay == "display-a")
        #expect(memory.lastSurface == .now)
        #expect(memory.styleSizes.isEmpty)
        #expect(memory.tuckedCenters.isEmpty)
        #expect(memory.size(for: .artOnly, on: "display-a") == nil)
    }

    @Test func eachStyleKeepsItsSizeOnEachDisplay() {
        var memory = WindowMemory()
        memory.setSize(PlayerSize(side: 320), for: .artOnly, on: "display-a")
        memory.setSize(PlayerSize(width: 440, height: 70), for: .strip, on: "display-a")
        memory.setSize(PlayerSize(side: 500), for: .artOnly, on: "display-b")
        #expect(memory.size(for: .artOnly, on: "display-a") == PlayerSize(side: 320))
        #expect(memory.size(for: .strip, on: "display-a") == PlayerSize(width: 440, height: 70))
        #expect(memory.size(for: .artOnly, on: "display-b") == PlayerSize(side: 500))
        #expect(memory.size(for: .strip, on: "display-b") == nil)
        #expect(memory.size(for: .title, on: "display-a") == nil)
    }

    /// Sizes saved for Glass, Data and Session, retired 2026-11-08 (DESIGN.md
    /// §13.19), and sizes that can't be read are dropped one by one; every
    /// other size stays, and none of the dropped ones is written back.
    @Test func sizesForRetiredStylesAreDroppedAndTheRestKept() throws {
        let json = """
        {
          "styleSizes": {
            "display-a": {
              "glass": { "width": 380, "height": 380 },
              "title": { "width": 320, "height": 72 },
              "data": { "width": 300, "height": 300 },
              "artOnly": "not a size"
            },
            "display-b": {
              "session": { "width": 280, "height": 280 },
              "bigArt": { "width": 260, "height": 392 }
            }
          },
          "lastSurface": "echo",
          "tuckedCenters": { "display-a": 512 }
        }
        """
        let memory = try JSONDecoder().decode(WindowMemory.self, from: Data(json.utf8))
        #expect(memory.styleSizes == [
            "display-a": ["title": PlayerSize(width: 320, height: 72)],
            "display-b": ["bigArt": PlayerSize(width: 260, height: 392)],
        ])
        #expect(memory.lastSurface == .echo)
        #expect(memory.tuckedCenters["display-a"] == 512)
        let written = String(decoding: try JSONEncoder().encode(memory), as: UTF8.self)
        for retired in ["glass", "data", "session"] {
            #expect(!written.contains("\"\(retired)\""), "\(retired)")
        }
    }

    @Test func everythingSurvivesARoundTrip() throws {
        var memory = WindowMemory()
        memory.placements["display-a"] = WindowPlacement(offsetX: 10, offsetY: 20, side: 300, surface: .echo, pin: .bottomLeft)
        memory.placements["display-b"] = WindowPlacement(offsetX: 300, offsetY: 120, side: 240, surface: .status)
        memory.lastDisplay = "display-a"
        memory.lastSurface = .status
        memory.setSize(PlayerSize(width: 400, height: 68), for: .strip, on: "display-a")
        memory.tuckedCenters["display-a"] = 742
        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(WindowMemory.self, from: data) == memory)
    }

    @Test func aDamagedFieldFallsBackWithoutLosingTheRest() throws {
        let json = """
        {
          "placements": {
            "display-a": { "offsetX": 1200, "offsetY": 600, "side": 280 }
          },
          "lastSurface": "somewhere-new",
          "styleSizes": "not a dictionary",
          "tuckedCenters": { "display-a": 512 }
        }
        """
        let memory = try JSONDecoder().decode(WindowMemory.self, from: Data(json.utf8))
        #expect(memory.placements["display-a"]?.side == 280)
        #expect(memory.placements["display-a"]?.surface == .now)
        #expect(memory.lastSurface == .now)
        #expect(memory.styleSizes.isEmpty)
        #expect(memory.tuckedCenters["display-a"] == 512)
    }

    @Test func eachDisplayRemembersItsOwnPin() throws {
        let json = """
        {
          "placements": {
            "display-a": { "offsetX": 16, "offsetY": 16, "side": 280, "pin": "bottomLeft" },
            "display-b": { "offsetX": 900, "offsetY": 500, "side": 280, "pin": "center" },
            "display-c": { "offsetX": 40, "offsetY": 40, "side": 280 }
          }
        }
        """
        let memory = try JSONDecoder().decode(WindowMemory.self, from: Data(json.utf8))
        #expect(memory.placements["display-a"]?.pin == .bottomLeft)
        #expect(memory.placements["display-b"]?.pin == .center)
        #expect(memory.placements["display-c"]?.pin == nil)
    }

    @Test func aPinThisBuildDoesNotKnowLeavesThePlayerUnpinned() throws {
        let json = """
        { "placements": { "display-a": { "offsetX": 40, "offsetY": 60, "side": 280, "pin": "somewhere-new" } } }
        """
        let memory = try JSONDecoder().decode(WindowMemory.self, from: Data(json.utf8))
        #expect(memory.placements["display-a"] == WindowPlacement(offsetX: 40, offsetY: 60, side: 280, surface: .now, pin: nil))
    }
}
