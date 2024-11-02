import 'package:frontend/features/auth/service/authentication/auth_service.dart';
import 'package:frontend/features/auth/service/authentication/auth_service_impl.dart';
import 'package:frontend/features/auth/service/authorization/account_service.dart';
import 'package:frontend/features/auth/service/authorization/account_service_impl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_provider.g.dart';

@Riverpod(keepAlive: true)
AuthService authService(AuthServiceRef ref) {
  return AuthServiceImpl();
}

@Riverpod(keepAlive: true)
AccountService accountService(AccountServiceRef ref) {
  return AccountServiceImpl();
}
