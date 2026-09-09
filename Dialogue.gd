class_name Dialogue
extends RefCounted

const GREETINGS := ["Hello!", "Hi there!", "Hey!"]
const COMPLAINTS := ["Stop that!", "Get back to work!", "Whoa, easy!", "Put me down!"]


static func random_greeting() -> String:
	return GREETINGS[randi() % GREETINGS.size()]


static func random_complaint() -> String:
	return COMPLAINTS[randi() % COMPLAINTS.size()]
