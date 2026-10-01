import SwiftUI

enum CalendarAutomaticEventHideKey {
    static func applicationDeadline(applicationID: String) -> String {
        "application-deadline:\(applicationID)"
    }

    static func congressAbstractDeadline(organizationID: String, congressID: String) -> String {
        "congress-abstract-deadline:\(organizationID):\(congressID)"
    }

    static func congressLateAbstractDeadline(organizationID: String, congressID: String) -> String {
        "congress-late-abstract-deadline:\(organizationID):\(congressID)"
    }

    static func congressFlight(organizationID: String, congressID: String, flightID: String) -> String {
        "congress-flight:\(organizationID):\(congressID):\(flightID)"
    }

    static func congressHotelCheckIn(organizationID: String, congressID: String) -> String {
        "congress-hotel-check-in:\(organizationID):\(congressID)"
    }

    static func congressHotelCheckIn(organizationID: String, congressID: String, hotelID: String) -> String {
        "congress-hotel-check-in:\(organizationID):\(congressID):\(hotelID)"
    }

    static func congressHotelCheckOut(organizationID: String, congressID: String) -> String {
        "congress-hotel-check-out:\(organizationID):\(congressID)"
    }

    static func congressHotelCheckOut(organizationID: String, congressID: String, hotelID: String) -> String {
        "congress-hotel-check-out:\(organizationID):\(congressID):\(hotelID)"
    }

    static func congressHotelStay(organizationID: String, congressID: String, hotelID: String, dayString: String) -> String {
        "congress-hotel-stay:\(organizationID):\(congressID):\(hotelID):\(dayString)"
    }
}

extension View {
    func calendarDateStatusOutline(
        isUncertain: Bool,
        isHiddenFromCalendar: Bool = false,
        cornerRadius: CGFloat = AppPalette.smallCornerRadius,
        uncertaintyColor: Color = AppPalette.statusMark(.warning)
    ) -> some View {
        modifier(
            CalendarDateStatusOutlineModifier(
                isUncertain: isUncertain,
                isHiddenFromCalendar: isHiddenFromCalendar,
                cornerRadius: cornerRadius,
                uncertaintyColor: uncertaintyColor
            )
        )
    }
}

private struct CalendarDateStatusOutlineModifier: ViewModifier {
    let isUncertain: Bool
    let isHiddenFromCalendar: Bool
    let cornerRadius: CGFloat
    let uncertaintyColor: Color

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isUncertain ? uncertaintyColor : Color.clear,
                        style: StrokeStyle(lineWidth: isUncertain ? 2.2 : 0, dash: [5, 3])
                    )
                    .allowsHitTesting(false)
            }
    }
}
