import Testing
@testable import AirPodsFeature

struct AirPodsProductTests {
    @Test func knownProductsMapToTheirSymbols() {
        let apple: UInt16 = 0x004C
        #expect(AirPodsProduct.lookup(vendorID: apple, productID: 0x2002)?.symbol == "airpods")
        #expect(AirPodsProduct.lookup(vendorID: apple, productID: 0x200F)?.symbol == "airpods")
        #expect(AirPodsProduct.lookup(vendorID: apple, productID: 0x2013)?.symbol == "airpods.gen3")
        for id: UInt16 in [0x2019, 0x201B, 0x201C, 0x201E, 0x2020, 0x2030, 0x2036] {
            #expect(AirPodsProduct.lookup(vendorID: apple, productID: id)?.symbol == "airpods.gen4")
        }
        for id: UInt16 in [0x200E, 0x2014, 0x2024, 0x2027] {
            #expect(AirPodsProduct.lookup(vendorID: apple, productID: id)?.symbol == "airpods.pro")
        }
        for id: UInt16 in [0x200A, 0x201F, 0x202D] {
            #expect(AirPodsProduct.lookup(vendorID: apple, productID: id)?.symbol == "airpods.max")
        }
    }

    @Test func unknownProductsAndOtherVendorsAreNotSupported() {
        #expect(AirPodsProduct.lookup(vendorID: 0x004C, productID: 0x1234) == nil)
        #expect(AirPodsProduct.lookup(vendorID: 0x0001, productID: 0x2002) == nil)
    }

    @Test func onlyMaxHasASingleBattery() {
        #expect(AirPodsProduct.lookup(vendorID: 0x004C, productID: 0x200A)?.hasSingleBattery == true)
        #expect(AirPodsProduct.lookup(vendorID: 0x004C, productID: 0x202D)?.hasSingleBattery == true)
        #expect(AirPodsProduct.lookup(vendorID: 0x004C, productID: 0x2014)?.hasSingleBattery == false)
        #expect(AirPodsProduct.lookup(vendorID: 0x004C, productID: 0x2002)?.hasSingleBattery == false)
    }
}

struct AirPodsBatteryTests {
    @Test func rawLevelsAreNormalized() {
        #expect(AirPodsBattery.level(fromRaw: 0) == nil)
        #expect(AirPodsBattery.level(fromRaw: 101) == nil)
        #expect(AirPodsBattery.level(fromRaw: 55) == 55)
        #expect(AirPodsBattery.level(fromRaw: 100) == 100)
        #expect(AirPodsBattery.level(fromRaw: 1) == 1)
    }

    @Test func lowestLevelPicksTheEmptierBud() {
        #expect(AirPodsBattery(left: 80, right: 35, chargingCase: 10).lowestLevel == 35)
    }

    @Test func lowestLevelUsesTheOneKnownBud() {
        #expect(AirPodsBattery(left: nil, right: 60).lowestLevel == 60)
        #expect(AirPodsBattery(left: 45, right: nil).lowestLevel == 45)
    }

    @Test func lowestLevelUsesTheSingleBattery() {
        #expect(AirPodsBattery(single: 70).lowestLevel == 70)
    }

    @Test func lowestLevelIsNilWithNothingKnown() {
        #expect(AirPodsBattery().lowestLevel == nil)
        #expect(AirPodsBattery(chargingCase: 90).lowestLevel == nil)
    }
}

struct ListeningModeTests {
    @Test func rawValuesMapBothWays() {
        #expect(ListeningMode(rawValue: 2) == .noiseCancellation)
        #expect(ListeningMode(rawValue: 3) == .transparency)
        #expect(ListeningMode(rawValue: 4) == .adaptive)
        #expect(ListeningMode.noiseCancellation.rawValue == 2)
        #expect(ListeningMode.transparency.rawValue == 3)
        #expect(ListeningMode.adaptive.rawValue == 4)
    }

    @Test func offAndUnknownValuesSelectNothing() {
        #expect(ListeningMode(rawValue: 1) == nil)
        #expect(ListeningMode(rawValue: 0) == nil)
        #expect(ListeningMode(rawValue: 5) == nil)
    }

    @Test func supportMaskDecodes() {
        #expect(ListeningMode.supported(mask: 0b111) == [.noiseCancellation, .transparency, .adaptive])
        #expect(ListeningMode.supported(mask: 0b011) == [.noiseCancellation, .transparency])
        #expect(ListeningMode.supported(mask: 0).isEmpty)
        #expect(ListeningMode.supported(mask: 0xFFFF_FF00 | 0b010) == [.transparency])
    }
}

struct AudioDeviceMatchingTests {
    private let address = "ac-90-85-12-34-56"

    @Test func uidWithTheAddressMatches() {
        #expect(AudioDeviceMatching.uid("AC-90-85-12-34-56:output", containsAddress: address))
        #expect(AudioDeviceMatching.uid("AC:90:85:12:34:56", containsAddress: address))
    }

    @Test func otherAddressesAndEmptyUIDsDoNotMatch() {
        #expect(!AudioDeviceMatching.uid("AC-90-85-12-34-57:output", containsAddress: address))
        #expect(!AudioDeviceMatching.uid("", containsAddress: address))
    }

    @Test func nameIsTheFallback() {
        #expect(AudioDeviceMatching.matches(uid: "unrelated", name: "My AirPods", address: address, deviceName: "My AirPods"))
        #expect(!AudioDeviceMatching.matches(uid: "unrelated", name: "Other", address: address, deviceName: "My AirPods"))
        #expect(!AudioDeviceMatching.matches(uid: nil, name: nil, address: address, deviceName: "My AirPods"))
        // Same name, but the UID names another pair's address.
        #expect(!AudioDeviceMatching.matches(uid: "11-22-33-44-55-66:output", name: "My AirPods", address: address, deviceName: "My AirPods"))
    }
}
