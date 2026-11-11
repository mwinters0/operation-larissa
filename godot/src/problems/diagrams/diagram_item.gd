class_name DiagramItem
extends RefCounted
## One thing a problem diagram draws: a picture, a piece of text or a filled rectangle.
##
## Teaches: describing a drawing as DATA first and painting it afterwards. A diagram builds
## a list of `DiagramItem`s from a problem record (pure logic, easy to unit-test), and the
## Control's `_draw()` only walks that list. All positions are window pixels of the original's
## 640 x 400 screen.

enum Kind { PICTURE, TEXT, RECT }
## LEFT: the text starts at `position.x`. CENTER: centred in the box `anchor_width` wide that starts at `position.x`.
## RIGHT: ends at `position.x`. MIDDLE: centred on the point `position.x` (a label on a wheel); the width is the font's, which
## only the drawing knows, so the item holds the POINT and `_draw` does the centring.
enum Align { LEFT, CENTER, RIGHT, MIDDLE }

var kind: Kind = Kind.PICTURE
## PICTURE: index of the picture in the type's art bundle. The texture is not kept: the diagram looks it up each time it draws (`DiagramBase.texture_of`), so the picture is the one of the skin in use.
var pic: int = -1
## Top-left corner (PICTURE, RECT) or the top of the text line (TEXT).
var position: Vector2 = Vector2.ZERO
## PICTURE: mirrored left to right (the original's "flip" flag).
var flip: bool = false
## TEXT: the string, how it sits at `position.x` (`anchor_width` wide box, centred or right-aligned) and its colour.
var text: String = ""
var align: Align = Align.LEFT
var anchor_width: float = 0.0
## RECT: size. TEXT and RECT: colour.
var size: Vector2 = Vector2.ZERO
var color: Color = Color.WHITE

