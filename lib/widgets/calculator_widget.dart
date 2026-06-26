import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';

class CalculatorWidget extends StatefulWidget {
  const CalculatorWidget({super.key});

  @override
  State<CalculatorWidget> createState() => _CalculatorWidgetState();
}

class _CalculatorWidgetState extends State<CalculatorWidget> {
  String _equation = "0";
  String _result = "0";

  void _buttonPressed(String buttonText) {
    setState(() {
      if (buttonText == "C") {
        _equation = "0";
        _result = "0";
      } else if (buttonText == "⌫") {
        if (_equation != "0") {
          _equation = _equation.substring(0, _equation.length - 1);
          if (_equation == "") {
            _equation = "0";
          }
        }
      } else if (buttonText == "=") {
        String expression = _equation;
        expression = expression.replaceAll('×', '*');
        expression = expression.replaceAll('÷', '/');

        try {
          Parser p = Parser();
          Expression exp = p.parse(expression);
          ContextModel cm = ContextModel();
          double eval = exp.evaluate(EvaluationType.REAL, cm);

          _result = eval.toString();
          if (_result.endsWith(".0")) {
            _result = _result.substring(0, _result.length - 2);
          }
        } catch (e) {
          _result = "خطأ";
        }
      } else {
        if (_equation == "0") {
          _equation = buttonText;
        } else {
          _equation = _equation + buttonText;
        }
      }
    });
  }

  Widget _buildButton(String text, Color color, {double height = 1}) {
    return Expanded(
      child: Container(
        height: 70 * height,
        margin: const EdgeInsets.all(4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 0,
            padding: EdgeInsets.zero,
          ),
          onPressed: () => _buttonPressed(text),
          child: Text(
            text,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          Container(
            alignment: Alignment.centerLeft, // لضمان عرض المعادلة الطويلة
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Text(_equation, style: TextStyle(fontSize: 24, color: Colors.grey[600])),
            ),
          ),
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_result, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF6F4E37))),
            ),
          ),
          const Divider(),
          Column(
            children: [
              Row(
                children: [
                  _buildButton("C", Colors.redAccent),
                  _buildButton("⌫", Colors.orangeAccent),
                  _buildButton("÷", Colors.blueAccent),
                  _buildButton("×", Colors.blueAccent),
                ],
              ),
              Row(
                children: [
                  _buildButton("7", Colors.grey[850]!),
                  _buildButton("8", Colors.grey[850]!),
                  _buildButton("9", Colors.grey[850]!),
                  _buildButton("-", Colors.blueAccent),
                ],
              ),
              Row(
                children: [
                  _buildButton("4", Colors.grey[850]!),
                  _buildButton("5", Colors.grey[850]!),
                  _buildButton("6", Colors.grey[850]!),
                  _buildButton("+", Colors.blueAccent),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildButton("1", Colors.grey[850]!),
                            _buildButton("2", Colors.grey[850]!),
                            _buildButton("3", Colors.grey[850]!),
                          ],
                        ),
                        Row(
                          children: [
                            _buildButton(".", Colors.grey[850]!),
                            _buildButton("0", Colors.grey[850]!),
                            _buildButton("00", Colors.grey[850]!),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildButton("=", const Color(0xFF6F4E37), height: 2.1),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}