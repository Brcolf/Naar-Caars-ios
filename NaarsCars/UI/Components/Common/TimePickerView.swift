//
//  TimePickerView.swift
//  NaarsCars
//
//  Custom time picker with hour, minute, and AM/PM wheels
//

import SwiftUI

/// Custom time picker component with wheel-style pickers for hour, minute, and AM/PM
/// Uses compositionalLayout to improve performance
struct TimePickerView: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var isAM: Bool
    
    // Pre-computed arrays to avoid recalculation on each render
    private let hours = Array(1...12)
    private let minutes = Array(stride(from: 0, to: 60, by: 5))
    
    var body: some View {
        HStack(spacing: 0) {
            // Hour picker (1-12)
            Picker("Hour", selection: $hour) {
                ForEach(hours, id: \.self) { h in
                    Text("\(h)")
                        .tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            .clipped()
            
            Text(":")
                .font(.title2)
                .padding(.horizontal, 2)
            
            // Minute picker (0-59, every 5 minutes)
            Picker("Minute", selection: $minute) {
                ForEach(minutes, id: \.self) { m in
                    Text(String(format: "%02d", m))
                        .tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            .clipped()
            
            // AM/PM picker
            Picker("Period", selection: $isAM) {
                Text("AM")
                    .tag(true)
                Text("PM")
                    .tag(false)
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            .clipped()
        }
        .frame(height: 120)
        .compositingGroup() // Improves rendering performance
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

