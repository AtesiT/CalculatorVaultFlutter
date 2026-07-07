import 'package:flutter/material.dart';
import 'vault_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expression = '';
  String _display = '0';

  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;
  bool _hasError = false;

  String _rawDigits = '';
  static const String _secretCode = '0101';

  static const int _maxSignificantDigits = 10;

  String _formatNumber(double value) {
    if (value.isInfinite || value.isNaN) return 'Error';

    String result;
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      result = value.toInt().toString();
    } else {
      result = value.toStringAsPrecision(_maxSignificantDigits);
      if (result.contains('.')) {
        result = result.replaceFirst(RegExp(r'0+$'), '');
        result = result.replaceFirst(RegExp(r'\.$'), '');
      }
      if (result.contains('e') || result.contains('E')) {
        result = value.toString();
      }
    }
    return result;
  }

  double? _tryParseDisplay() => double.tryParse(_display);

  void _onButtonPressed(String value) {
    if (value == 'C') {
      setState(_resetAll);
      return;
    }

    if (_hasError) return;

    if (value == '=') {
      if (_operator == null &&
          _firstOperand == null &&
          _rawDigits == _secretCode) {
        _navigateToVault();
        return;
      }
      setState(_handleEquals);
      return;
    }

    setState(() {
      if (value == '⌫') {
        _handleBackspace();
      } else if (value == '±') {
        _handleToggleSign();
      } else if (value == '%') {
        _handlePercent();
      } else if (value == '.') {
        _handleDecimalPoint();
      } else if (['÷', '×', '−', '+'].contains(value)) {
        _handleOperator(value);
      } else {
        _handleDigit(value);
      }
    });
  }

  Future<void> _navigateToVault() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VaultScreen()),
    );
    setState(_resetAll);
  }

  void _resetAll() {
    _expression = '';
    _display = '0';
    _firstOperand = null;
    _operator = null;
    _shouldResetDisplay = false;
    _hasError = false;
    _rawDigits = '';
  }

  void _handleDigit(String digit) {
    if (_shouldResetDisplay) {
      _display = digit;
      _rawDigits = digit;
      _shouldResetDisplay = false;
    } else {
      _display = (_display == '0') ? digit : _display + digit;
      _rawDigits += digit;
    }
  }

  void _handleDecimalPoint() {
    if (_shouldResetDisplay) {
      _display = '0.';
      _shouldResetDisplay = false;
    } else if (!_display.contains('.')) {
      _display += '.';
    }
    _rawDigits = ''; 
  }

  void _handleBackspace() {
    if (_shouldResetDisplay) return;
    if (_display.length > 1) {
      _display = _display.substring(0, _display.length - 1);
    } else {
      _display = '0';
    }
    if (_rawDigits.isNotEmpty) {
      _rawDigits = _rawDigits.substring(0, _rawDigits.length - 1);
    }
  }

  void _handleToggleSign() {
    final value = _tryParseDisplay();
    if (value == null) return;
    _display = _formatNumber(value * -1);
    _rawDigits = '';
  }

  void _handlePercent() {
    final value = _tryParseDisplay();
    if (value == null) return;
    _display = _formatNumber(value / 100);
    _rawDigits = '';
  }

  void _handleOperator(String op) {
    final currentValue = _tryParseDisplay();
    if (currentValue == null) return;

    if (_firstOperand != null && _operator != null && !_shouldResetDisplay) {
      final result = _calculate(_firstOperand!, currentValue, _operator!);
      if (result == null) {
        _triggerError();
        return;
      }
      _firstOperand = result;
      _expression = '${_formatNumber(result)} $op';
      _display = _formatNumber(result);
    } else {
      _firstOperand = currentValue;
      _expression = '${_formatNumber(currentValue)} $op';
    }

    _operator = op;
    _shouldResetDisplay = true;
    _rawDigits = '';
  }

  void _handleEquals() {
    final currentValue = _tryParseDisplay();
    if (currentValue == null || _operator == null || _firstOperand == null) {
      return;
    }

    final result = _calculate(_firstOperand!, currentValue, _operator!);
    if (result == null) {
      _triggerError();
      return;
    }

    _expression =
        '${_formatNumber(_firstOperand!)} $_operator ${_formatNumber(currentValue)} =';
    _display = _formatNumber(result);

    _firstOperand = null;
    _operator = null;
    _shouldResetDisplay = true;
    _rawDigits = '';
  }

  double? _calculate(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        if (b == 0) return null;
        return a / b;
      default:
        return null;
    }
  }

  void _triggerError() {
    _display = 'Error';
    _expression = '';
    _hasError = true;
    _firstOperand = null;
    _operator = null;
    _shouldResetDisplay = false;
    _rawDigits = '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: Alignment.bottomRight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _expression,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _display,
                      style: TextStyle(
                        color: _hasError ? Colors.redAccent : Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w300,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    _buildRow(['C', '⌫', '%', '÷']),
                    _buildRow(['7', '8', '9', '×']),
                    _buildRow(['4', '5', '6', '−']),
                    _buildRow(['1', '2', '3', '+']),
                    _buildRow(['±', '0', '.', '=']),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> labels) {
    return Expanded(
      child: Row(
        children: labels.map((label) => _buildButton(label)).toList(),
      ),
    );
  }

  Widget _buildButton(String label) {
    final bool isOperator = ['÷', '×', '−', '+', '='].contains(label);
    final bool isFunction = ['C', '⌫', '%', '±'].contains(label);

    Color bgColor;
    Color textColor = Colors.white;

    if (isOperator) {
      bgColor =
          label == '=' ? const Color(0xFF0A84FF) : const Color(0xFF2C2C2E);
      textColor = label == '=' ? Colors.white : const Color(0xFF0A84FF);
    } else if (isFunction) {
      bgColor = const Color(0xFF3A3A3C);
      textColor = Colors.white;
    } else {
      bgColor = const Color(0xFF232325);
    }

    final bool isActiveOperator = isOperator &&
        label != '=' &&
        _operator == label &&
        _shouldResetDisplay;

    if (isActiveOperator) {
      bgColor = const Color(0xFF0A84FF);
      textColor = Colors.white;
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _onButtonPressed(label),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}