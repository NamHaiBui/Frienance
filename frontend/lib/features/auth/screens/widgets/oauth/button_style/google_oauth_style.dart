import 'package:flutter/widgets.dart';
import 'package:firebase_ui_oauth/firebase_ui_oauth.dart';

const _googleWhite = Color.fromARGB(255, 255, 255, 255);
const _googleBlue = Color.fromRGBO(15, 82, 186, 1);
const _googleDark = Color.fromARGB(0, 170, 30, 30);

// ThemeColor(dark, light)
const _backgroundColor = ThemedColor(_googleWhite, _googleWhite);
const _color = ThemedColor(_googleDark, _googleBlue);
const _iconBackgroundColor = ThemedColor(_googleDark, _googleWhite);

const _iconSvg = '''
<svg width="33" height="32" viewBox="0 0 33 32" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M4.58469 10.0121C6.77862 5.65452 11.2876 2.66663 16.4998 2.66663C20.0937 2.66663 23.1118 3.98789 25.421 6.13936L21.5968 9.96361C20.215 8.64243 18.4573 7.96965 16.4998 7.96965C13.0271 7.96965 10.0876 10.3151 9.03924 13.4666C8.7725 14.2666 8.62098 15.1212 8.62098 16C8.62098 16.8788 8.7725 17.7333 9.03924 18.5333C10.0876 21.6848 13.0271 24.0302 16.4998 24.0302C18.2937 24.0302 19.821 23.5576 21.015 22.7576C22.427 21.8121 23.3665 20.4 23.6756 18.7333H16.4998V13.5757H29.0573C29.215 14.4484 29.2998 15.3576 29.2998 16.303C29.2998 20.3636 27.8453 23.7817 25.324 26.103C23.118 28.1394 20.0998 29.3333 16.4998 29.3333C11.2876 29.3333 6.77862 26.3454 4.58469 21.9878C3.68168 20.1878 3.1665 18.1514 3.1665 16C3.1665 13.8485 3.68168 11.8121 4.58469 10.0121Z" fill="#0F52BA"/>
</svg>
''';

const _iconSrc = ThemedIconSrc(_iconSvg, _iconSvg);

class GoogleOAuthButtonStyle extends ThemedOAuthProviderButtonStyle {
  const GoogleOAuthButtonStyle();

  @override
  ThemedColor get backgroundColor => _backgroundColor;

  @override
  ThemedColor get color => _color;

  @override
  ThemedIconSrc get iconSrc => _iconSrc;

  @override
  ThemedColor get iconBackgroundColor => _iconBackgroundColor;

  @override
  double get iconPadding => 2;

  @override
  String get assetsPackage => 'firebase_ui_oauth_google';
}
