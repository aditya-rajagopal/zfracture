---
title: Out of bounds simulation
status: todo
priority: high
priority_value: 44
owner: adira
created: 2025-12-15T23:54:07Z
tags: 
- renderer
---

We need to simulate entities that are outside the screen. We can divide the Map into chunks and only update
the entities that are in chunks the player has visited. We will not have a very large world so we will load all
the entities needed for the particular level at once as dormant entities and add them to the active entity list
When a particular chunk enters the simlulation region. We will update all entities that are active.
We currently dont need the active entities to interact with dormant ones? Maybe there is a scenario where that might be
needed? Excample if an enemy in the simulation region is the type that will go alert a bigger group of enemies when
attacked it is possible that the entity that is to be activated is not in the active entity list.
The simulation region is a rectangle that is centered around the player.
We should spawn all entities that are needed for a level, even the ones that are "hidden" from the player and only
activate when the player does certain actions like activating a mechanic or triggering a boss fight.
