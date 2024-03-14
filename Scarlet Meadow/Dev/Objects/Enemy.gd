extends CharacterBody3D
class_name Enemy

# Get the gravity from the project settings to be synced with RigidBody nodes.
var GRAVITY = 45.0;


func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()
