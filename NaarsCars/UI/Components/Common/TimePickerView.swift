//
//  TimePickerView.swift
//  NaarsCars
//
//  Custom time picker with hour, minute, and AM/PM wheels
//

import SwiftUI

/// Custom time picker component with wheel-style pickers for hour, minute, and AM/PM
struct TimePickerView: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var isAM: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Hour picker (1-12)
            Picker("Hour", selection: $hour) {
                ForEach(1...12, id: \.self) { h in
                    Text("\(h)")
                        .tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            
            Text(":")
                .font(.title2)
                .padding(.horizontal, 4)
            
            // Minute picker (0-59, every 5 minutes)
            Picker("Minute", selection: $minute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m))
                        .tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            
            // AM/PM picker
            Picker("Period", selection: $isAM) {
                Text("AM")
                    .tag(true)
                Text("PM")
                    .tag(false)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 120)
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

