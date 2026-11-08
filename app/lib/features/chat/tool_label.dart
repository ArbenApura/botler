// WHAT A TOOL EVENT SAYS ABOUT ITSELF: ITS KIND ("family"), WHAT IT IS ABOUT ("subject") AND HOW LONG IT TOOK.
// The server builds the label from checked arguments only. An older server sends none, and then the row keeps its old wording.

// -- MODULES -- //
import '../../core/json.dart';

// -- TYPES -- //

/// The label of one tool event. Both parts are null when the event carries none.
typedef ToolLabel = ({String? family, String? subject, int? ms});

// -- FUNCTIONS -- //

/// Reads the label and the time off a tool_start or tool event, or off a stored one. Anything of the wrong shape is ignored.
ToolLabel toolLabelOf(Json e) {
  final label = asJson(e['label']);
  String? family;
  String? subject;
  final f = label['family'];
  final s = label['subject'];
  if (f is String && f.isNotEmpty) family = f;
  if (s is String && s.trim().isNotEmpty) subject = s.trim();
  final raw = e['ms'];
  final ms = raw is num && raw >= 0 ? raw.round() : null;
  return (family: family, subject: subject, ms: ms);
}
