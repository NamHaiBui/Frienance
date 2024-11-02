class StringsForAuth {
  // google oauth
  static const signInWithGoogle = 'Sign in with Google';
  static const signUpWithGoogle = 'Sign up with Google';
  // email_and_password
  static const signIn = 'Sign in';
  static const signUp = 'Sign up';
  //  forgot_password
  static const sendPasswordResetRequest = 'Send Password Reset Request';
  static const backTo = 'Back to ';
  static const resetMyPassword = 'Reset My Password';
  static const forgotYourPassword = 'Forgot your password?';
  // footer

  static const newUser = 'New here?';
  static const createAnAccount = 'Create an account';
  const StringsForAuth._();

  //Sign up/ sign in
  static RegExp emailRegex = RegExp(r'^[\w-]+(\.[\w-]+)*@[\w-]+(\.[\w-]+)+$');
  static const String fieldNameEmail = 'Email Address';
  static const String hintTextEmail = 'Enter your email';
  static const String invalidEmailMessage =
      'Please enter a valid email address.';
  static const String fieldNamePassword = 'Password';
  static const String hintTextPasswordLogin = 'Enter your password';
  static const String hintTextPasswordOther = 'Type something';
  static const String requiredPasswordMessage = 'Please enter password.';
  static const String shortPasswordMessage =
      'Password must be at least 6 characters long.';
  static const int minPasswordLength = 6;
  static const String fieldNameConfirmPassword = 'Confirm Password';
  static const String hintTextConfirmPassword = 'Type something';
  static const String passwordMismatchMessage = 'Passwords do not match!';
}
