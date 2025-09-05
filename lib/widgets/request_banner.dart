import 'package:flutter/material.dart';
import 'package:cashlink/services/notification_service.dart';
import 'package:cashlink/widgets/notification_banner.dart';

class RequestBanner extends StatefulWidget {
  final Widget child;

  const RequestBanner({super.key, required this.child});

  @override
  State<RequestBanner> createState() => _RequestBannerState();
}

class _RequestBannerState extends State<RequestBanner> {
  @override
  void initState() {
    super.initState();
    // This initializes notifications for the current user
    // The service listens for transactions where this user is the RECIPIENT
    NotificationService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: NotificationService().currentNotification,
      builder: (context, notification, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              widget.child,
              // This banner appears when someone ELSE sends a request TO this user
              if (notification != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: NotificationBanner(
                    data: notification,
                    onNavigateToAgreement: () {
                      // Takes the recipient to the agreement screen
                      Navigator.of(context).pushNamed('/agreement', arguments: {
                        'myTxId': notification['myTxId'],
                        'otherTxId': notification['otherTxId'],
                      });
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
