import CoreGraphics
@testable import HumUI
import Testing

@Suite("Player metrics")
struct PlayerMetricsTests {
    @Test(arguments: [
        (168, PlayerSizeClass.small), (239, .small),
        (240, .medium), (280, .medium), (379, .medium),
        (380, .large), (640, .large),
    ] as [(CGFloat, PlayerSizeClass)])
    func sideMapsToSizeClass(side: CGFloat, expected: PlayerSizeClass) {
        #expect(PlayerSizeClass(side: side) == expected)
    }

    @Test func sidesClampToTheAllowedRange() {
        #expect(PlayerMetrics.clampedSide(100) == PlayerMetrics.minimumSide)
        #expect(PlayerMetrics.clampedSide(1000) == PlayerMetrics.maximumSide)
        #expect(PlayerMetrics.clampedSide(300) == 300)
    }

    @Test(arguments: [PlayerSizeClass.small, .medium, .large])
    func controlsKeepTheirOrderAndMinimumTargets(sizeClass: PlayerSizeClass) {
        let play = ControlSizing.play(sizeClass)
        let skip = ControlSizing.skip(sizeClass)
        let tertiary = ControlSizing.tertiary(sizeClass)
        #expect(play.hit > skip.hit)
        #expect(skip.hit > tertiary.hit)
        for control in [play, skip, tertiary, .icon, .cardPlay(sizeClass)] {
            #expect(control.glyph < control.backing)
            #expect(control.backing <= control.hit)
        }
        #expect(play.hit >= ControlSizing.minimumHit(sizeClass, isTertiary: false))
        #expect(skip.hit >= ControlSizing.minimumHit(sizeClass, isTertiary: false))
        #expect(tertiary.hit >= ControlSizing.minimumHit(sizeClass, isTertiary: true))
    }

    @Test func outsetIsHalfTheDifference() {
        #expect(ControlSizing(glyph: 10, backing: 24, hit: 32).outset == 4)
    }

    @Test func crowdedNeighborsSplitTheGapAtItsMidpoint() {
        let extents = HitTargets.extents(outsets: [2, 2, 2], gaps: [8, 2])
        // 2 + 2 fits in 8, so the first pair keeps its outsets.
        #expect(extents[0] == (leading: 2, trailing: 2))
        #expect(extents[1].leading == 2)
        // 2 + 2 doesn't fit in 2: each side gets half.
        #expect(extents[1].trailing == 1)
        #expect(extents[2] == (leading: 1, trailing: 2))
    }

    @Test func aSingleControlKeepsItsOutset() {
        let extents = HitTargets.extents(outsets: [4], gaps: [])
        #expect(extents.count == 1)
        #expect(extents[0] == (leading: 4, trailing: 4))
    }

    @Test func overlappingBackingsGetNoExtraReach() {
        let extents = HitTargets.extents(outsets: [2, 2], gaps: [-3])
        #expect(extents[0].trailing == 0)
        #expect(extents[1].leading == 0)
    }
}
