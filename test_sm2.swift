import Foundation
import ServiceManagement

let service = SMAppService.daemon(plistName: "com.ibrardev.BatteryGuard.Helper.plist")
do {
    try service.register()
    print("Success")
} catch {
    print("Error: \(error)")
}
