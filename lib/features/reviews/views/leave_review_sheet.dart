import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_sheet.dart';
import '../../../core/widgets/landa_toast.dart';
import '../controllers/review_controller.dart';
import '../models/review_models.dart';
import 'widgets/rating_stars.dart';

/// Asks the user to rate something they have finished with, and posts it.
///
/// Resolves true when a review was accepted. Callers use that to refresh:
/// the thing being reviewed usually shows its own new average straight after.
///
/// [transactionId] is the booking, job or agreement the review comes out of.
/// Required rather than optional: it is what the backend checks the author
/// against, and a review with nothing behind it is the kind that gets bought.
Future<bool> openLeaveReviewSheet(
  BuildContext context, {
  required ReviewSubject subject,
  required String subjectId,
  required String transactionId,
  required String subjectName,
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: keyboard > 0 ? screenHeight : screenHeight * 0.75,
        ),
        child: _LeaveReviewSheet(
          subject: subject,
          subjectId: subjectId,
          transactionId: transactionId,
          subjectName: subjectName,
        ),
      );
    },
  );
  return posted ?? false;
}

class _LeaveReviewSheet extends StatefulWidget {
  final ReviewSubject subject;
  final String subjectId;
  final String transactionId;
  final String subjectName;

  const _LeaveReviewSheet({
    required this.subject,
    required this.subjectId,
    required this.transactionId,
    required this.subjectName,
  });

  @override
  State<_LeaveReviewSheet> createState() => _LeaveReviewSheetState();
}

class _LeaveReviewSheetState extends State<_LeaveReviewSheet> {
  final _commentController = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// What the chosen star count means, said in words.
  ///
  /// Stars alone are ambiguous: three out of five reads as "fine" to one
  /// person and "bad" to another, and the person writing a review is making
  /// a judgement that affects someone's livelihood. Naming it lets them
  /// correct a rating they did not mean.
  String get _ratingWord {
    switch (_rating) {
      case 5:
        return 'Excellent, everything as promised';
      case 4:
        return 'Good, a few small things';
      case 3:
        return 'Fine, nothing special either way';
      case 2:
        return 'Poor, several problems';
      case 1:
        return 'Bad, I would warn someone off';
      default:
        return 'Tap a star to rate';
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      LandaToast.error(context, 'Pick a star rating first.');
      return;
    }

    final controller = context.read<ReviewController>();
    final posted = await controller.submitReview(
      subject: widget.subject,
      subjectId: widget.subjectId,
      transactionId: widget.transactionId,
      rating: _rating,
      comment: _commentController.text,
    );
    if (!mounted) return;

    if (!posted) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not post that review. Try again in a moment.',
      );
      return;
    }
    Navigator.pop(context, true);
    LandaToast.success(context, 'Thanks, your review is up.');
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = context.select<ReviewController, bool>(
      (c) => c.isSubmitting,
    );

    return LandaSheet(
      icon: Icons.star_outline_rounded,
      title: 'How was it?',
      subtitle:
          '${widget.subjectName}. Your review is public and shown with your '
          'name, so keep it to what actually happened.',
      footer: LandaSheetButton(
        label: 'Post review',
        icon: Icons.send_rounded,
        isLoading: isSubmitting,
        onPressed: isSubmitting || _rating == 0 ? null : _submit,
      ),
      children: [
        const SizedBox(height: 4),
        RatingStarsInput(
          value: _rating,
          onChanged: (value) => setState(() => _rating = value),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _ratingWord,
            textAlign: TextAlign.center,
            style: AppTheme.bodyText(
              context,
              color: _rating == 0
                  ? AppTheme.mutedTextColor(context)
                  : AppTheme.secondaryTextColor(context),
            ),
          ),
        ),
        const SizedBox(height: 22),

        const LandaFieldLabel('Say more (optional)'),
        TextField(
          controller: _commentController,
          maxLines: 4,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          style: AppTheme.bodyText(context),
          decoration: landaInputDecoration(
            context,
            hint: 'What should the next person know?',
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reviews can only be left after a completed booking, and '
                'cannot be edited once posted.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
