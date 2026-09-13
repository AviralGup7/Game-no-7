class_name CampaignMission
extends RefCounted
## Immutable-after-load story objective record.
var id: String ## JSON key: id.
var title: String ## JSON key: title.
var brief: String ## JSON key: brief.
var sector: String ## JSON key: sector.
var kind: String ## JSON key: kind.
var targets: Array[String] = [] ## JSON key: targets.
var requires: Array[String] = [] ## JSON key: requires.
var reward: CampaignReward ## JSON key: reward.
