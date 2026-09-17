class_name Dialogue
extends RefCounted

const GREETINGS := ["Hello!", "Hi there!", "Hey!"]
const COMPLAINTS := ["Stop that!", "Get back to work!", "Whoa, easy!", "Put me down!"]
const WAKE_UPS := ["Huh? What?", "I'm up, I'm up!", "Who dares wake me?", "Five more minutes..."]


static func random_greeting() -> String:
	return GREETINGS[randi() % GREETINGS.size()]


static func random_complaint() -> String:
	return COMPLAINTS[randi() % COMPLAINTS.size()]


static func random_wake_up() -> String:
	return WAKE_UPS[randi() % WAKE_UPS.size()]
