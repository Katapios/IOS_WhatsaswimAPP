//
//  CalendarView.swift
//  Whatsaswim
//
//  Created by Денис Сергеевич on 05.12.2025.
//

import SwiftUI

struct CalendarView: View {
    @StateObject private var dataManager = TrainingDataManager.shared
    @State private var currentDate = Date()
    @State private var selectedDate: Date?
    @State private var showDetailView = false
    @State private var daysInMonth: [Date] = []
    @State private var isLoading = true
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок с месяцем и годом
            HStack {
                Button(action: {
                    changeMonth(by: -1)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                Text(dateFormatter.string(from: currentDate).capitalized)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        dataManager.refresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    
                    Button(action: {
                        changeMonth(by: 1)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Дни недели
            HStack(spacing: 0) {
                ForEach(weekdayIndices, id: \.self) { index in
                    Text(weekdayName(for: index))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            
            // Календарная сетка
            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Загрузка календаря...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                if dataManager.trainingDates.isEmpty && !isLoading {
                    // Показываем сообщение, если нет тренировок
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("Нет тренировок")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Завершите тренировку на часах, чтобы увидеть её в календаре")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button(action: {
                            dataManager.refresh()
                            loadCalendarData()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Обновить")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    Spacer()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(daysInMonth, id: \.self) { date in
                            CalendarDayView(
                                date: date,
                                isCurrentMonth: calendar.isDate(date, equalTo: currentDate, toGranularity: .month),
                                isToday: calendar.isDateInToday(date),
                                hasTraining: dataManager.hasTraining(on: date),
                                isSelected: selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!),
                                onTap: {
                                    let hasTraining = dataManager.hasTraining(on: date)
                                    if hasTraining {
                                        selectedDate = date
                                        showDetailView = true
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            
            Spacer()
        }
        .onAppear {
            // Обновляем данные при появлении календаря
            dataManager.refresh()
            loadCalendarData()
        }
        .task {
            // Дополнительная загрузка при первом появлении
            dataManager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trainingResultsSaved)) { _ in
            // Обновляем данные при получении уведомления о сохранении результатов
            print("📬 Получено уведомление о сохранении результатов тренировки")
            dataManager.refresh()
            // Небольшая задержка для синхронизации App Group
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateDaysInMonth()
            }
        }
        .onChange(of: currentDate) {
            updateDaysInMonth()
            // Обновляем данные при смене месяца
            dataManager.refresh()
        }
        .onChange(of: dataManager.trainingDates) {
            // Обновляем календарь при изменении данных о тренировках
            updateDaysInMonth()
        }
        .sheet(isPresented: $showDetailView, onDismiss: {
            selectedDate = nil
            // Обновляем данные после закрытия детального экрана
            dataManager.refresh()
        }) {
            if let date = selectedDate {
                TrainingDetailView(date: date)
            }
        }
    }
    
    private var weekdayIndices: [Int] {
        // Начинаем с понедельника (1)
        return Array(1...7)
    }
    
    private func weekdayName(for index: Int) -> String {
        let weekdaySymbols = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        return weekdaySymbols[index - 1]
    }
    
    private func updateDaysInMonth() {
        guard let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) else {
            daysInMonth = []
            return
        }
        
        // Находим первый день недели месяца (может быть предыдущий месяц)
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Преобразуем в понедельник = 1
        let adjustedFirstWeekday = (firstWeekday + 5) % 7 + 1
        
        // Находим первый день для отображения (может быть из предыдущего месяца)
        let daysToSubtract = adjustedFirstWeekday - 1
        guard let firstDisplayDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth) else {
            daysInMonth = []
            return
        }
        
        // Создаем 42 дня (6 недель)
        var days: [Date] = []
        for i in 0..<42 {
            if let date = calendar.date(byAdding: .day, value: i, to: firstDisplayDate) {
                days.append(date)
            }
        }
        
        daysInMonth = days
    }
    
    private func loadCalendarData() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak dataManager] in
            // Принудительно обновляем данные
            dataManager?.refresh()
            // Небольшая задержка для синхронизации App Group
            Thread.sleep(forTimeInterval: 0.2)
            DispatchQueue.main.async {
                self.updateDaysInMonth()
                self.isLoading = false
                // Дополнительная проверка после загрузки
                print("📅 Календарь загружен. Дат с тренировками: \(dataManager?.trainingDates.count ?? 0)")
            }
        }
    }
    
    private func changeMonth(by months: Int) {
        if let newDate = calendar.date(byAdding: .month, value: months, to: currentDate) {
            currentDate = newDate
            updateDaysInMonth()
        }
    }
}

// MARK: - Calendar Day View
struct CalendarDayView: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let hasTraining: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: {
            onTap()
        }) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isCurrentMonth
                            ? (isToday ? .blue : (hasTraining ? .blue : .primary))
                            : .secondary
                    )
                
                if hasTraining {
                    Circle()
                        .fill(isSelected ? .blue : .cyan)
                        .frame(width: 6, height: 6)
                } else {
                    Spacer()
                        .frame(height: 6)
                }
            }
            .frame(width: 44, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color.blue.opacity(0.2)
                            : (isToday ? Color.blue.opacity(0.15) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }
}

// MARK: - Training Date Wrapper for Sheet
struct TrainingDateWrapper: Identifiable, Equatable {
    let id: String
    let date: Date
    
    init(date: Date) {
        self.date = date
        self.id = Calendar.current.startOfDay(for: date).timeIntervalSince1970.description
    }
    
    static func == (lhs: TrainingDateWrapper, rhs: TrainingDateWrapper) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Training Detail View
struct TrainingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    
    @StateObject private var dataManager = TrainingDataManager.shared
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if let results = dataManager.getTrainingResults(for: date) {
                    VStack(spacing: 20) {
                        // Заголовок с датой и временем
                        VStack(spacing: 8) {
                            Text(dateFormatter.string(from: date).capitalized)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            if let savedResult = dataManager.getSavedResult(for: date) {
                                Text("Время тренировки: \(timeFormatter.string(from: savedResult.date))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                        
                        // Основные показатели - большие карточки
                        HStack(spacing: 16) {
                            // Длительность
                            VStack(spacing: 8) {
                                Image(systemName: "clock.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                Text("Длительность")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatTime(results.duration))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            
                            // Дистанция
                            VStack(spacing: 8) {
                                Image(systemName: "figure.pool.swim")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)
                                Text("Дистанция")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(results.distance)) м")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.cyan.opacity(0.1))
                            )
                        }
                        .padding(.horizontal)
                        
                        // Стили плавания
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .foregroundStyle(.blue)
                                Text("Стили плавания")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal)
                            
                            ForEach(results.styles, id: \.name) { style in
                                StyleCard(style: style)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Дополнительная информация
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                                Text("Дополнительная информация")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                DetailRow(
                                    icon: "thermometer",
                                    label: "Температура воды",
                                    value: String(format: "%.1f°C", results.waterTemperature),
                                    color: .orange
                                )
                                
                                DetailRow(
                                    icon: "arrow.down.circle",
                                    label: "Средняя глубина",
                                    value: String(format: "%.1f м", results.averageDepth),
                                    color: .blue
                                )
                                
                                DetailRow(
                                    icon: "speedometer",
                                    label: "Средняя скорость",
                                    value: String(format: "%.1f м/мин", calculateAverageSpeed(distance: results.distance, duration: results.duration)),
                                    color: .green
                                )
                                
                                DetailRow(
                                    icon: "figure.pool.swim",
                                    label: "Всего гребков",
                                    value: "\(results.styles.reduce(0) { $0 + $1.totalStrokes })",
                                    color: .cyan
                                )
                                
                                // Статистика по стилям
                                if results.styles.count > 1 {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Распределение по стилям:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 16)
                                        
                                        ForEach(results.styles, id: \.name) { style in
                                            HStack {
                                                Text(style.name)
                                                    .font(.subheadline)
                                                Spacer()
                                                Text("\(Int(style.totalStrokes)) гребков")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Text("(\(Int(calculateDistanceForStyle(style: style, totalDistance: results.distance, totalStrokes: results.styles.reduce(0) { $0 + $1.totalStrokes }))) м)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 16)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.1))
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 20)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)
                        Text("Данные о тренировке не найдены")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Попробуйте обновить данные")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Результаты тренировки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func calculateAverageSpeed(distance: Double, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return distance / (duration / 60.0)
    }
    
    private func calculateDistanceForStyle(style: SwimStyle, totalDistance: Double, totalStrokes: Int) -> Double {
        guard totalStrokes > 0 else { return 0 }
        let styleRatio = Double(style.totalStrokes) / Double(totalStrokes)
        return totalDistance * styleRatio
    }
}

// MARK: - Style Card
struct StyleCard: View {
    let style: SwimStyle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок стиля
            HStack {
                Image(systemName: styleIcon(for: style.name))
                    .font(.title3)
                    .foregroundStyle(styleColor(for: style.name))
                Text(style.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(style.totalStrokes)")
                        .font(.headline)
                    Text("гребков")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Сегменты по 25м
            if !style.segments25m.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Гребков на каждые 25м:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    // Отображаем сегменты в виде сетки
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Array(style.segments25m.enumerated()), id: \.offset) { index, strokes in
                            VStack(spacing: 4) {
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(strokes)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("гребков")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }
    
    private func styleIcon(for styleName: String) -> String {
        switch styleName {
        case "Кроль":
            return "arrow.right.circle.fill"
        case "Баттерфляй":
            return "waveform.path"
        case "Брасс":
            return "arrow.up.and.down.circle.fill"
        case "На спине":
            return "arrow.up.circle.fill"
        default:
            return "figure.pool.swim"
        }
    }
    
    private func styleColor(for styleName: String) -> Color {
        switch styleName {
        case "Кроль":
            return .blue
        case "Баттерфляй":
            return .orange
        case "Брасс":
            return .green
        case "На спине":
            return .purple
        default:
            return .cyan
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

