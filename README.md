# TuKuai

We usually refer to these people as "Tu Kuai".

## Introduction

### Condition: 

The game starts with at least 3 players, players cannot leave until the game ends.

### Rules:

The system randomly selects a number between 1 and 100. Players takes turns to guess the number with the specified range. If a player guesses the number correctly, the player loses. If the guess is incorrect, the game continues. The game ends when a player guesses the correct number, and that player is the loser.

### Game Process:

1. The system randomly selects a number between 1 and 100.

2. Players takes turns to guess the number with the specified range.

3. If a player guesses the number correctly, the player loses.

4. If the guess is incorrect, the game continues.

5. The game ends when a player guesses the correct number, and that player is the loser.



### Design Principle:

Keep it simple and funtional, with continuous optimization rather than over-optimizing from the beginning.

### Interface Design:

In skynet, from the perspective of the `actor` at the underlying layer, communication is done through the messages; from the perspective of the `actor` at the application layer, communication is done through the APIs.

### Interface Segeration Principle:

Clients should not be forced to depend on methods they do not use: from the perspective of the secure encapsulation, only the interface that clients need; service should not depend on each other's implementation.

**Agent**:

- **Login**: Implement the login functionality; handles reconnection after disconnection.
- **Ready**: Prepares and forwards to the lobby, joining the matchmaking queue.
- **Guess**: Guesses a number, forwards to the room.
- **Help**: Lists all operation instructions.
- **Quit**: Exits.

**Hall:**

- **Ready**: Joins the matchmaking queue.
- **Offline**: Handles user disconnection, removes the user from the matchmaking queue.

**Room:**

- **Start:** Initializes the room.
- **Online**: Handles user online. If the user is in a game, informs about the game progress.
- **Offline**: Handles user going offline, notifies other users in the room.
- **Guess:** Guesses a number, advances the game process.



Here's the English translation of the text in the image:

**Game Demonstration**

- **Client-side**

  ```bash
  telnet 127.0.0.1 8888
  ```

- **Server-side**

  First start redis, then start skynet

  ```bash
  1  redis-server redis.conf
  2  ./skynet/skynet config.game
  ```

- **How to Optimize**

1. Do not create agent services in real-time; consider pre-creation. Allocate agent addresses only after user authentication is successful to avoid unnecessary allocation.
2. Create a gate service: perform login verification, process verification, and heartbeat detection. Allocate an agent only after successful verification.
3. If the agent's functionality is relatively simple, consider creating a fixed number of agents.
4. If the room's functionality is relatively simple, consider creating a fixed number of rooms.
5. For games with tens of thousands of concurrent online players, agents and rooms need to be pre-allocated. Long-term operation can lead to service memory bloat and increase the burden on Lua garbage collection.
6. Restart service strategy: Create the same number of agent service groups. New incoming players are assigned to new service groups. Old players in old service groups, after completing their operations, are retired until the old service groups have no players left, at which point the old service groups exit. This ensures that old service groups only handle old tasks, and new connecting users work in the new service groups.

​    