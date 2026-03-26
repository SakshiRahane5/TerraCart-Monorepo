import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'contact_support_screen.dart';

class HelpFAQScreen extends StatefulWidget {
  const HelpFAQScreen({super.key});

  @override
  State<HelpFAQScreen> createState() => _HelpFAQScreenState();
}

class _HelpFAQScreenState extends State<HelpFAQScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedFaqKeys = <String>{};

  static const List<Map<String, String>> _faqData = [
    {
      'questionKey': 'faq.q1',
      'answerKey': 'faq.a1',
    },
    {
      'questionKey': 'faq.q2',
      'answerKey': 'faq.a2',
    },
    {
      'questionKey': 'faq.q3',
      'answerKey': 'faq.a3',
    },
    {
      'questionKey': 'faq.q4',
      'answerKey': 'faq.a4',
    },
    {
      'questionKey': 'faq.q5',
      'answerKey': 'faq.a5',
    },
    {
      'questionKey': 'faq.q6',
      'answerKey': 'faq.a6',
    },
    {
      'questionKey': 'faq.q7',
      'answerKey': 'faq.a7',
    },
    {
      'questionKey': 'faq.q8',
      'answerKey': 'faq.a8',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_FaqItem> get _filteredFaqs {
    final allFaqs = _faqData
        .map(
          (faq) => _FaqItem(
            questionKey: faq['questionKey'] ?? '',
            answerKey: faq['answerKey'] ?? '',
            expanded: _expandedFaqKeys.contains(faq['questionKey']),
          ),
        )
        .toList();
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return allFaqs;
    return allFaqs.where((item) {
      return context.tr(item.questionKey).toLowerCase().contains(query) ||
          context.tr(item.answerKey).toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('help.title')),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 700 ? 24.0 : 16.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(context),
                      const SizedBox(height: 16),
                      _buildSearchCard(context),
                      const SizedBox(height: 12),
                      _buildFaqContent(context, constraints.maxWidth),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('help.header_title'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('help.header_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ContactSupportScreen(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.support_agent, size: 18),
            label: Text(context.tr('help.need_more_help')),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          labelText: context.tr('help.search_hint'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildFaqContent(BuildContext context, double maxWidth) {
    final filtered = _filteredFaqs;
    if (filtered.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 44,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('help.no_match'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    final isWide = maxWidth >= 900;
    final cardWidth = isWide ? (maxWidth - 16) / 2 : maxWidth;

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: filtered
          .map(
            (faq) => SizedBox(
              width: cardWidth,
              child: _buildFAQItem(context, faq),
            ),
          )
          .toList(),
    );
  }

  Widget _buildFAQItem(BuildContext context, _FaqItem faq) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: faq.expanded
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: faq.expanded ? 0.07 : 0.04),
            blurRadius: faq.expanded ? 12 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.help_outline_rounded,
            color: AppColors.primary,
            size: 18,
          ),
        ),
        title: Text(
          context.tr(faq.questionKey),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
        ),
        trailing: Icon(
          faq.expanded ? Icons.expand_less : Icons.expand_more,
          color: AppColors.primary,
        ),
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedFaqKeys.add(faq.questionKey);
            } else {
              _expandedFaqKeys.remove(faq.questionKey);
            }
          });
        },
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.tr(faq.answerKey),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String questionKey;
  final String answerKey;
  final bool expanded;

  _FaqItem({
    required this.questionKey,
    required this.answerKey,
    required this.expanded,
  });
}
