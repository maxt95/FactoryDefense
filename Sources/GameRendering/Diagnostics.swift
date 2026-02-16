import Foundation

public enum RenderDiagnostics {
    public static let notificationName = Notification.Name("FactoryDefense.RenderDiagnostics")
    public static let messageKey = "message"

    public static func post(_ message: String) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [messageKey: message]
        )
    }
}
