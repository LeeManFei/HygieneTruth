import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class HorizontalStepTracker extends StatelessWidget {
  final int currentStep;
  final List<String> stepTitles;

  const HorizontalStepTracker({
    super.key,
    required this.currentStep,
    required this.stepTitles,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const activeColor = AppTheme.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final itemCount = stepTitles.length;
          final segmentWidth = totalWidth / itemCount;

          return Column(
            children: [
              // Perfectly Centered Circles & Connecting Line Bar
              SizedBox(
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Connecting Line spanning between circle centers
                    Positioned(
                      left: segmentWidth / 2,
                      right: segmentWidth / 2,
                      height: 3,
                      child: Row(
                        children: List.generate(itemCount - 1, (idx) {
                          final isLineCompleted = idx < currentStep;
                          return Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 350),
                              height: 3,
                              color: isLineCompleted ? activeColor : (isDark ? Colors.white12 : Colors.grey.shade200),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Step Circle Nodes
                    Row(
                      children: List.generate(itemCount, (index) {
                        final isCompleted = index < currentStep;
                        final isCurrent = index == currentStep;

                        return SizedBox(
                          width: segmentWidth,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCompleted
                                    ? activeColor
                                    : isCurrent
                                        ? activeColor.withValues(alpha: 0.15)
                                        : (isDark ? const Color(0xFF282828) : Colors.grey.shade100),
                                border: Border.all(
                                  color: isCompleted || isCurrent ? activeColor : (isDark ? Colors.white24 : Colors.grey.shade300),
                                  width: isCurrent ? 2.5 : 1.5,
                                ),
                              ),
                              child: Center(
                                child: isCompleted
                                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                                    : isCurrent
                                        ? Container(
                                            width: 14,
                                            height: 14,
                                            decoration: const BoxDecoration(
                                              color: activeColor,
                                              shape: BoxShape.circle,
                                            ),
                                          )
                                        : Icon(
                                            Icons.location_on_outlined,
                                            size: 16,
                                            color: isDark ? Colors.white38 : Colors.grey.shade400,
                                          ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Step Titles Aligned Directly Below Each Circle
              Row(
                children: List.generate(itemCount, (index) {
                  final isCompleted = index < currentStep;
                  final isCurrent = index == currentStep;

                  return SizedBox(
                    width: segmentWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          stepTitles[index],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isCurrent || isCompleted ? FontWeight.bold : FontWeight.w500,
                            color: isCurrent
                                ? (isDark ? Colors.white : AppTheme.navyColor)
                                : isCompleted
                                    ? activeColor
                                    : (isDark ? Colors.white38 : Colors.grey.shade500),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}
