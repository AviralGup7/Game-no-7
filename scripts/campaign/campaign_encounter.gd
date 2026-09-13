class_name CampaignEncounter
extends RefCounted
## Immutable-after-load encounter record.
var id: String ## JSON key: id.
var sector: String ## JSON key: sector.
var center: Vector2 ## JSON key: center.
var activate_radius: float ## JSON key: activate_radius.
var members: Array[CampaignMember] = [] ## JSON key: members.
