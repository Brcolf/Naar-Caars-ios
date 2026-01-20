//
//  TimePickerView.swift
//  NaarsCars
//
//  Custom time picker with compact inline menus
//

import SwiftUI

/// Compact time picker component with inline menu-style pickers
struct TimePickerView: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var isAM: Bool
    
    // Pre-computed arrays to avoid recalculation on each render
    private let hours = Array(1...12)
    private let minutes = Array(stride(from: 0, to: 60, by: 5))
    
    /// Formatted time string for display
    private var timeString: String {
        let minuteStr = String(format: "%02d", minute)
        let period = isAM ? "AM" : "PM"
        return "\(hour):\(minuteStr) \(period)"
    }
    
    var body: some View {
        HStack {
            Text("Time")
            
            Spacer()
            
            HStack(spacing: 2) {
                // Hour picker
                Menu {
                    ForEach(hours, id: \.self) { h in
                        Button(action: { hour = h }) {
                            if h == hour {
                                Label("\(h)", systemImage: "checkmark")
                            } else {
                                Text("\(h)")
                            }
                        }
                    }
                } label: {
                    Text("\(hour)")
                        .frame(minWidth: 28)
                }
                .buttonStyle(.bordered)
                
                Text(":")
                    .foregroundColor(.secondary)
                
                // Minute picker
                Menu {
                    ForEach(minutes, id: \.self) { m in
                        Button(action: { minute = m }) {
                            if m == minute {
                                Label(String(format: "%02d", m), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%02d", m))
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%02d", minute))
                        .frame(minWidth: 28)
                }
                .buttonStyle(.bordered)
                
                // AM/PM picker
                Menu {
                    Button(action: { isAM = true }) {
                        if isAM {
                            Label("AM", systemImage: "checkmark")
                        } else {
                            Text("AM")
                        }
                    }
                    Button(action: { isAM = false }) {
                        if !isAM {
                            Label("PM", systemImage: "checkmark")
                        } else {
                            Text("PM")
                        }
                    }
                } label: {
                    Text(isAM ? "AM" : "PM")
                        .frame(minWidth: 36)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var hour = 9
        @State var minute = 30
        @State var isAM = true
        
        var body: some View {
            TimePickerView(hour: $hour, minute: $minute, isAM: $isAM)
                .padding()
        }
    }
    
    return PreviewWrapper()
}

