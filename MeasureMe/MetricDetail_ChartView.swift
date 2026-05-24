import SwiftUI
import Charts
import SwiftData

// MARK: - Chart View

extension MetricDetailView {

    var chartView: some View {
        Chart {
            if showTrendline, let trend = cachedTrendlineSegment {
                ForEach(trendlinePoints(trend), id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Trend", "Trend")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(AppColorRoles.stateSuccess.opacity(0.96))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
            }

            ForEach(chartRenderSamples, id: \.persistentModelID) { s in
                AreaMark(
                    x: .value("Date", s.date),
                    yStart: .value("Baseline", cachedYDomain.lowerBound),
                    yEnd: .value("Value", displayValue(s.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(ClaudeLightStyle.areaFill(accent: measurementsTheme.accent, colorScheme: colorScheme))

                LineMark(
                    x: .value("Date", s.date),
                    y: .value("Value", displayValue(s.value))
                )
                .interpolationMethod(.monotone)
                .lineStyle(.init(lineWidth: 2.5))
                .foregroundStyle(measurementsTheme.accent)

                if shouldRenderAllChartPoints {
                    PointMark(
                        x: .value("Date", s.date),
                        y: .value("Value", displayValue(s.value))
                    )
                    .symbol(Circle())
                    .symbolSize(20)
                    .foregroundStyle(measurementsTheme.accent)
                }

                if s.persistentModelID == latestRenderedSampleID {
                    PointMark(
                        x: .value("Latest Date", s.date),
                        y: .value("Latest Value", displayValue(s.value))
                    )
                    .symbol(Circle())
                    .symbolSize(82)
                    .foregroundStyle(measurementsTheme.accent.opacity(0.26))

                    if !shouldRenderAllChartPoints {
                        PointMark(
                            x: .value("Latest Date Marker", s.date),
                            y: .value("Latest Value Marker", displayValue(s.value))
                        )
                        .symbol(Circle())
                        .symbolSize(24)
                        .foregroundStyle(measurementsTheme.accent)
                    }
                }
            }

            if let goal = currentGoal {
                let goalValue = displayValue(goal.targetValue)
                RuleMark(y: .value("Goal", goalValue))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            if let scrubbedDate {
                RuleMark(x: .value("Selected Date", scrubbedDate))
                    .foregroundStyle(AppColorRoles.textSecondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let scrubbedPrimarySample {
                    PointMark(
                        x: .value("Selected Date", scrubbedPrimarySample.date),
                        y: .value("Selected Value", displayValue(scrubbedPrimarySample.value))
                    )
                    .symbol(Circle())
                    .symbolSize(58)
                    .foregroundStyle(AppColorRoles.textPrimary)
                }
            }
        }
        .chartYScale(domain: cachedYDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppColorRoles.borderSubtle)
                AxisTick().foregroundStyle(AppColorRoles.borderStrong)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppColorRoles.borderSubtle)
                AxisTick().foregroundStyle(AppColorRoles.borderStrong)
                AxisValueLabel()
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .frame(height: 168)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateChartWidthIfNeeded(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, newValue in
                        updateChartWidthIfNeeded(newValue)
                    }
            }
        }
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleChartTap(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                handleChartDragChanged(value, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                if chartScrubState != .idle {
                                    endChartScrubbing()
                                }
                            }
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            if let scrubbedDate {
                scrubbedOverlay(for: scrubbedDate)
                    .padding(.top, 6)
                    .padding(.leading, 6)
            }
        }
        .clipped()
        .accessibilityIdentifier("metric.detail.chart")
        .accessibilityChartDescriptor(MetricChartAXDescriptor(descriptor: chartDescriptor))
        .accessibilityLabel(AppLocalization.string("accessibility.chart", kind.title))
        .accessibilityHint(AppLocalization.string("accessibility.chart.hint"))
    }
}
