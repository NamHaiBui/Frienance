import 'package:firebase_auth/firebase_auth.dart' hide OAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth/firebase_ui_oauth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

// // for debugging
// import 'dart:developer' as devtools show log;

// extension Log on Object {
//   void log() => devtools.log(toString());
// }

typedef FontFamily = String?;

/// A builder that is invoked to build  widget that indicates an error.
typedef ErrorBuilder = Widget Function(Exception e);

typedef DifferentProvidersFoundCallback = void Function(
  List<String> providers,
  AuthCredential? credential,
);

/// A calback called when the user signs in
typedef SignedInCallback = void Function(UserCredential credential);

/// A base widget that allows authentication using OAuth providers
class OAuthButtonBase extends StatefulWidget {
  /// Text that would be displayed on the button
  final String label;

  ///Font size of the button label. Padding of the buttons is calculated
  ///to meet the provider design requirements
  final double fontSize;

  ///A widget that would be displayed while the button is in loading state
  final Widget loadingIndicator;

  /// Type of Authentication action the widget do :SignIn, SignOut, etc.
  final AuthAction? action;

  /// Instance of FirebaseAuth
  final FirebaseAuth? auth;

  /// A callback that is being called when the button is tapped
  final void Function()? onTap;
  final OAuthProvider provider;

  /// When the user credential associated with the email does not use the current Provider
  final DifferentProvidersFoundCallback? onDifferentProvidersFound;

  /// A callback function for when the user sign in
  final SignedInCallback? onSignedIn;

  /// A callback for when an error occurs
  final void Function(Exception exception)? onError;

  /// A callback for when the user cancels the sign in
  final VoidCallback? onCancelled;

  /// Indicates whether the default tap action shoud be overridden.
  /// If set to `true`, the authentication logic is not executed
  /// and should be handled by the user.
  final bool overrideDefaultTapAction;

  /// Indicates whether the sign in process is in progress
  final bool isLoading;

  final double height;

  final double width;

  final FontFamily fontFamily;

  /// Styling
  final ThemedOAuthProviderButtonStyle? style;

  const OAuthButtonBase({
    super.key,
    required this.label,
    this.fontSize = 18,
    required this.loadingIndicator,
    this.action,
    this.auth,
    this.onTap,
    required this.provider,
    this.onSignedIn,
    this.onDifferentProvidersFound,
    this.onError,
    this.onCancelled,
    required this.overrideDefaultTapAction,
    this.isLoading = false,
    this.style,
    required this.height,
    required this.width,
    required this.fontFamily,
  }) : assert(!overrideDefaultTapAction || onTap != null);

  @override
  State<OAuthButtonBase> createState() {
    return _OAuthButtonBaseState();
  }
}

class _OAuthButtonBaseState extends State<OAuthButtonBase>
    implements OAuthListener {
  late bool isLoading = widget.isLoading;

  @override
  FirebaseAuth get auth => widget.auth ?? FirebaseAuth.instance;

  @override
  OAuthProvider get provider => widget.provider;
  @override
  void initState() {
    super.initState();

    widget.provider.auth = widget.auth ?? FirebaseAuth.instance;
    widget.provider.authListener = this;
  }

  @override
  void didUpdateWidget(covariant OAuthButtonBase oldWidget) {
    if (oldWidget.isLoading != widget.isLoading) {
      isLoading = widget.isLoading;
    }

    super.didUpdateWidget(oldWidget);
  }

  /// called before an attempt to fetch available providers for email
  @override
  void onBeforeProvidersForEmailFetch() {
    setState(() {
      isLoading = true;
    });
  }

  /// Called before the authentication process start
  @override
  void onBeforeSignIn() {
    setState(() {
      isLoading = true;
    });
  }

  @override
  void onCanceled() {
    setState(() {
      isLoading = false;
    });

    widget.onCancelled?.call();
  }

  /// Called if the credential was successfully linked with the user account
  @override
  void onCredentialLinked(AuthCredential credential) {
    setState(() {
      isLoading = false;
    });
  }

  @override
  void onCredentialReceived(AuthCredential credential) {
    // When receiving credential, start the process to link the credentials with the user
    setState(() {
      isLoading = true;
    });
  }

  /// Called when the available providers for the email were successfully fetched
  @override
  void onDifferentProvidersFound(
      String email, List<String> providers, AuthCredential? credential) {
    widget.onDifferentProvidersFound?.call(providers, credential);
  }

  @override
  void onError(Object error) {
    try {
      defaultOnAuthError(provider, error);
    } on Exception catch (err) {
      widget.onError?.call(err);
    }
  }

  @override
  void onMFARequired(MultiFactorResolver resolver) {
    //TODO: To be implemented when needed
  }

  void _signIn() {
    final platform = Theme.of(context).platform;

    if (widget.overrideDefaultTapAction) {
      widget.onTap!.call();
    } else {
      provider.signIn(platform, widget.action ?? AuthAction.signIn);
    }
  }

  @override
  void onSignedIn(UserCredential credential) {
    setState(() {
      isLoading = false;
    });
    // send a record to Firestore to save the credentials of this user
    widget.onSignedIn?.call(credential);
  }

  Widget _buildMaterial(
    BuildContext context,
    OAuthProviderButtonStyle style,
    double borderRadius,
  ) {
    final br = BorderRadius.circular(borderRadius);
    return Stack(children: [
      _ButtonContainer(
        borderColor: Theme.of(context).colorScheme.primary,
        borderRadius: br,
        color: widget.label.isEmpty
            ? style.iconBackgroundColor
            : style.backgroundColor,
        height: widget.height,
        width: widget.label.isEmpty ? 0 : widget.width,
        child: _ButtonContent(
          assetsPackage:
              style.assetsPackage, // Just the name you can give to this style
          iconSrc: style.iconSrc, // svg File for an img
          iconPadding: style.iconPadding, // padding

          iconBackgroundColor: style.iconBackgroundColor, // Background Color
          isLoading: isLoading,
          label: widget.label,
          fontFamily: widget.fontFamily,
          width: widget.width,
          fontSize: widget.fontSize,
          textColor: style.color, // textColor
          loadingIndicator: widget.loadingIndicator,
          borderRadius: br,
          borderColor: style.color, // border color
        ),
      ),
      _MaterialForeground(onTap: () => _signIn()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final ThemedOAuthProviderButtonStyle style = widget.style ?? provider.style;
    const borderRadius = 100.0;

    return _buildMaterial(
      context,
      style.withBrightness(brightness), // Dark theme or light theme
      borderRadius,
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final double width;
  final String iconSrc;
  final double iconPadding;
  final String assetsPackage;
  final String label;
  final bool isLoading;
  final Color textColor;
  final double fontSize;
  final Widget loadingIndicator;
  final BorderRadius borderRadius;
  final Color borderColor;
  final Color iconBackgroundColor;

  final FontFamily fontFamily;

  const _ButtonContent(
      {required this.width,
      required this.iconSrc,
      required this.iconPadding,
      required this.assetsPackage,
      required this.label,
      required this.isLoading,
      required this.fontSize,
      required this.textColor,
      required this.loadingIndicator,
      required this.borderRadius,
      required this.borderColor,
      required this.iconBackgroundColor,
      required this.fontFamily});

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: EdgeInsets.only(top: iconPadding * 3),
      child: SizedBox(
        height: fontSize,
        width: fontSize,
        child: loadingIndicator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget icon = Padding(
      padding: EdgeInsets.all(iconPadding * 2),
      child: SvgPicture.string(
        iconSrc,
        width: width * 0.07,
        height: width * 0.07,
      ),
    );

    if (label.isNotEmpty) {
      final content = isLoading
          ? _buildLoadingIndicator()
          : Text(
              label,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: fontSize),
            );

      icon = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          SizedBox(width: width * 0.02),
          content,
        ],
      );
    } else if (isLoading) {
      icon = _buildLoadingIndicator();
    }
    return icon;
  }
}

class _MaterialForeground extends StatelessWidget {
  final VoidCallback onTap;

  const _MaterialForeground({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ButtonContainer extends StatelessWidget {
  final double height;
  final double width;
  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Widget child;

  const _ButtonContainer({
    required this.height,
    required this.color,
    required this.borderColor,
    required this.borderRadius,
    required this.child,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            minimumSize: Size(width, height),
            shape: RoundedRectangleBorder(
                side: BorderSide(width: 1.2, color: borderColor),
                borderRadius: BorderRadius.circular(100))),
        child: Padding(
          padding: EdgeInsets.all(width * 0.8 / 96),
          child: ClipRRect(
            clipBehavior: Clip.hardEdge,
            borderRadius: borderRadius,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
