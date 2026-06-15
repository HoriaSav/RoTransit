import 'package:flutter/material.dart';

const _estimatedSnackBarHeight = 56.0;
const _topGap = 12.0;
const _horizontalInset = 16.0;
const _verticalOffsetFraction = 0.15;

EdgeInsets topSnackBarMargin(BuildContext context) {
  final media = MediaQuery.of(context);
  final screenHeight = media.size.height;
  return EdgeInsets.only(
    left: _horizontalInset,
    right: _horizontalInset,
    bottom: screenHeight -
        media.padding.top -
        _topGap -
        _estimatedSnackBarHeight -
        screenHeight * _verticalOffsetFraction,
  );
}

/// Shows a [SnackBar] anchored below the status bar instead of above the nav.
void showAppSnackBar(BuildContext context, SnackBar snackBar) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      key: snackBar.key,
      content: snackBar.content,
      action: snackBar.action,
      duration: snackBar.duration,
      elevation: snackBar.elevation,
      shape: snackBar.shape,
      backgroundColor: snackBar.backgroundColor,
      behavior: SnackBarBehavior.floating,
      margin: topSnackBarMargin(context),
      padding: snackBar.padding,
      width: snackBar.width,
      dismissDirection: snackBar.dismissDirection,
      showCloseIcon: snackBar.showCloseIcon,
      closeIconColor: snackBar.closeIconColor,
      onVisible: snackBar.onVisible,
    ),
  );
}
