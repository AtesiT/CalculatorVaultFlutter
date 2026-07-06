import 'package:flutter/material.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expression = '';
  String _display = '0';

  // Временный обработчик нажатий - просто UI-заглушка.
  void _onButtonPressed(String value) {
    setState(() {
      if (value == 'C') {
        _display = '0';
        _expression = '';
        return;
      }

      if (value == '⌫') {
        if (_display.length > 1) {
          _display = _display.substring(0, _display.length - 1);
        } else {
          _display = '0';
        }
        return;
      }

      if (_display == '0' && value != '.') {
        _display = value;
      } else {
        _display += value;
      }
    });
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
                      style: const TextStyle(
                        color: Colors.white,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      bgColor = label == '='
          ? const Color(0xFF0A84FF) // акцентный синий для "="
          : const Color(0xFF2C2C2E);
      textColor = label == '=' ? Colors.white : const Color(0xFF0A84FF);
    } else if (isFunction) {
      bgColor = const Color(0xFF3A3A3C);
      textColor = Colors.white;
    } else {
      bgColor = const Color(0xFF232325);
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