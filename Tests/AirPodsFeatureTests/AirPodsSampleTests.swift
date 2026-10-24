import Testing
@testable import AirPodsFeature

@MainActor
struct AirPodsSampleTests {
    @Test func aSampleShowsAsTheConnectedAirPods() {
        let model = AirPodsModel()
        model.showSample(.pro)
        #expect(model.isShowingSample)
        #expect(model.connection == AirPodsSample.pro.connection)
        #expect(model.battery == AirPodsBattery(left: 86, right: 74, chargingCase: 58))
        #expect(model.volume == 0.6)
        #expect(model.supportedModes == ListeningMode.allCases)
        #expect(model.listeningMode == .noiseCancellation)
    }

    @Test func maxHasOneBatteryAndLowBatteryIsUnderTheWarningLevel() {
        #expect(AirPodsSample.max.connection.product.hasSingleBattery)
        #expect(AirPodsSample.max.battery.single != nil)
        #expect(AirPodsSample.max.battery.left == nil)
        #expect((AirPodsSample.lowBattery.battery.lowestLevel ?? 100) <= 20)
    }

    @Test func refreshAndControlsChangeOnlyTheSample() {
        let model = AirPodsModel()
        model.showSample(.pro)
        model.refresh()
        #expect(model.battery == AirPodsSample.pro.battery)
        model.setVolume(0.2)
        #expect(model.volume == 0.2)
        model.setListeningMode(.transparency)
        #expect(model.listeningMode == .transparency)
    }

    @Test func disconnectingClearsTheSample() {
        let model = AirPodsModel()
        model.showSample(.max)
        model.disconnect()
        #expect(!model.isShowingSample)
        #expect(model.connection == nil)
        #expect(model.battery == AirPodsBattery())
        #expect(model.volume == nil)
        #expect(model.supportedModes.isEmpty)
    }
}
