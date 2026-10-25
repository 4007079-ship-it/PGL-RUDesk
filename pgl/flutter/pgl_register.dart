import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../../common.dart';
import '../../utils/http_service.dart' as http;
import './dialog.dart';

class PglRegistration {
  final String email;
  final String password;
  const PglRegistration(this.email, this.password);
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

Future<String?> _register(String email, String password) async {
  final url = await bind.mainGetApiServer();
  if (url.isEmpty) {
    return 'Сервер аккаунтов не настроен';
  }
  final http.Response resp;
  try {
    resp = await http.post(Uri.parse('$url/api/admin/user/register'),
        body: jsonEncode({
          'username': email,
          'email': email,
          'password': password,
          'confirm_password': password,
        }));
  } catch (e) {
    return 'Нет связи с сервером: $e';
  }
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(decode_http_response(resp));
  } catch (_) {
    return 'Ошибка сервера (HTTP ${resp.statusCode})';
  }
  if (body['code'] == 0) {
    return null;
  }
  final msg = (body['message'] ?? '').toString();
  if (msg.isEmpty || msg.contains('Операция не удалась')) {
    return 'Эта почта уже зарегистрирована';
  }
  return msg;
}

Future<PglRegistration?> pglRegisterDialog() async {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  String? emailMsg;
  String? passwordMsg;
  String? confirmMsg;
  var inProgress = false;

  return gFFI.dialogManager.show<PglRegistration?>((setState, close, context) {
    submit() async {
      if (inProgress) return;
      final e = email.text.trim();
      String? em, pm, cm;
      if (!_emailRe.hasMatch(e)) {
        em = 'Введите почту, например name@mail.ru';
      } else if (e.length > 32) {
        em = 'Почта длиннее 32 символов не поддерживается';
      }
      if (password.text.length < 6) {
        pm = 'Пароль — минимум 6 символов';
      } else if (password.text.length > 32) {
        pm = 'Пароль — максимум 32 символа';
      }
      if (confirm.text != password.text) {
        cm = 'Пароли не совпадают';
      }
      if (em != null || pm != null || cm != null) {
        setState(() {
          emailMsg = em;
          passwordMsg = pm;
          confirmMsg = cm;
        });
        return;
      }
      setState(() => inProgress = true);
      final err = await _register(e, password.text);
      if (err == null) {
        close(PglRegistration(e, password.text));
        return;
      }
      setState(() {
        inProgress = false;
        emailMsg = err;
      });
    }

    return CustomAlertDialog(
      title: const Text('Регистрация'),
      contentBoxConstraints: const BoxConstraints(minWidth: 400),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8.0),
          DialogTextField(
            title: 'Почта',
            controller: email,
            prefixIcon: const Icon(Icons.mail_outline),
            keyboardType: TextInputType.emailAddress,
            errorText: emailMsg,
          ),
          PasswordWidget(
            controller: password,
            autoFocus: false,
            title: 'Пароль',
            errorText: passwordMsg,
          ),
          PasswordWidget(
            controller: confirm,
            autoFocus: false,
            title: 'Повторите пароль',
            errorText: confirmMsg,
          ),
          if (inProgress) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        dialogButton('Отмена', onPressed: () => close(null), isOutline: true),
        dialogButton('Зарегистрироваться', onPressed: inProgress ? null : submit),
      ],
      onSubmit: submit,
      onCancel: () => close(null),
    );
  });
}
