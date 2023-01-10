import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mono_flutter/extensions/map.dart';
import 'package:mono_flutter/extensions/num.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'models/mono_event.dart';
import 'models/mono_event_data.dart';
import 'mono_html.dart';

class MonoWebView extends StatefulWidget {
  /// Public API key gotten from your mono dashboard
  final String apiKey, reAuthCode;

  final String? reference;

  /// a function called when transaction succeeds
  final Function(String code)? onSuccess;

  /// a function called when user clicks the close button on mono's page
  final Function()? onClosed;

  /// a function called when the mono widget loads
  final Function()? onLoad;

  /// An overlay widget to display over webview if page fails to load
  final Widget? error;

  final Function(MonoEvent event, MonoEventData data)? onEvent;

  final Map<String, dynamic>? config;

  const MonoWebView(
      {Key? key,
      required this.apiKey,
      this.error,
      this.onEvent,
      this.onSuccess,
      this.onClosed,
      this.onLoad,
      this.reference,
      this.config,
      this.reAuthCode = ''})
      : super(key: key);

  @override
  MonoWebViewState createState() => MonoWebViewState();
}

class MonoWebViewState extends State<MonoWebView> {
  WebViewController _webViewController = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);
  // final url = 'https://connect.withmono.com/?key=';
  bool isLoading = false;
  bool hasError = false;

  late String contentBase64;

  // await controller.loadUrl('data:text/html;base64,$contentBase64');

  @override
  void initState() {
    contentBase64 = base64Encode(const Utf8Encoder().convert(MonoHtml.build(
        widget.apiKey, widget.reference ?? 15.getRandomString, widget.config, widget.reAuthCode)));

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _webViewController = WebViewController.fromPlatformCreationParams(params);

    if (_webViewController.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(kDebugMode);
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (widget.onClosed != null) widget.onClosed!();
        return true;
      },
      child: Material(
        child: GestureDetector(
            onTap: () {
              ///  WidgetsBinding.instance.focusManager.primaryFocus?.unfocus();
            },
            child: SafeArea(
              child: Stack(children: [
                Container(
                  // margin: EdgeInsets.only(top: 30),
                  decoration: BoxDecoration(border: Border.all(color: Colors.transparent)),
                  child: WebViewWidget(
                    controller: _webViewController
                      ..loadHtmlString('data:text/html;base64,$contentBase64')
                      ..setNavigationDelegate(
                        NavigationDelegate(
                          onPageStarted: (String url) {
                            // hasForward = await _webViewController?.canGoForward();
                            setState(() {
                              isLoading = true;
                              hasError = false;
                            });
                          },
                          onWebResourceError: (err) async {
                            // print(err);
                            isLoading = false;
                            setState(() {
                              hasError = true;
                            });
                          },
                          onPageFinished: (String url) async {
                            isLoading = false;
                            setState(() {});
                          },
                        ),
                      )
                      ..addJavaScriptChannel('MonoClientInterface',
                          onMessageReceived: (JavaScriptMessage message) {
                        if (kDebugMode) print('MonoClientInterface, ${message.message}');
                        var res = json.decode(message.message);
                        if (kDebugMode) {
                          print('MonoClientInterface, ${(res as Map<String, dynamic>)}');
                        }
                        handleResponse(res as Map<String, dynamic>);
                      }),
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{}
                      ..add(Factory<TapGestureRecognizer>(() => TapGestureRecognizer()
                        ..onTapDown = (tap) {
                          SystemChannels.textInput
                              .invokeMethod('TextInput.hide'); //This will hide keyboard on tapdown
                        })),
                  ),
                ),
                if (isLoading) const Center(child: CupertinoActivityIndicator()),
                if (hasError) widget.error ?? _error
              ]),
            )),
      ),
    );
  }

  /// A default overlay widget to display over webview if page fails to load
  Widget get _error => Container(
      alignment: Alignment.center,
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
                child: const Text('Reload'),
                onPressed: () {
                  _webViewController.reload();
                }),
          ),
          const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('Sorry An error occurred could not connect with Mono',
                  textAlign: TextAlign.center)),
        ],
      ));

  /// parse event from javascript channel
  void handleResponse(Map<String, dynamic>? body) {
    String? key = body!['type'];
    if (key != null) {
      switch (key) {

        // case 'mono.connect.widget.account_linked':
        case 'mono.modal.linked':
          var response = body['response'];
          if (response == null) return;
          var code = response['code'];
          if (widget.onSuccess != null) widget.onSuccess!(code);
          if (mounted) Navigator.of(context).pop(code);
          break;
        // case 'mono.connect.widget.closed':
        case 'mono.modal.closed':
          if (widget.onClosed != null) widget.onClosed!();
          if (mounted) Navigator.of(context).pop();
          break;
        case 'mono.modal.onLoad':
          if (mounted && widget.onLoad != null) widget.onLoad!();
          break;

        default:
          final event = MonoEvent.unknown.fromString(key.split('.').last);
          if (widget.onEvent != null) {
            widget.onEvent!(event, MonoEventData.fromJson(body.getKey('data')));
          }
          break;
      }
    }
  }
}
