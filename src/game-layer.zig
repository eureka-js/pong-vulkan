const cglm = @import("bindings/cglm.zig").cglm;

const std = @import("std");

const GameInputHandler      = @import("game-input-handler.zig").GameInputHandler;
const AudioHandler          = @import("audio-handler.zig").AudioHandler;
const Particle              = @import("particle.zig").Particle;
const ParticleManager       = @import("particle-manager.zig").ParticleManager;
const WorldEntityManager    = @import("world-entity-manager.zig").WorldEntityManager;
const BoundingBox           = @import("bounding-box.zig").BoundingBox;
const ParticleBoundingBox   = @import("particle-bounding-box.zig").ParticleBoundingBox;
const PlayerManager         = @import("player-manager.zig").PlayerManager;
const ThreadContextRuntime  = @import("thread-context.zig").ThreadContextRuntime;
const ThreadContextComptime = @import("thread-context.zig").ThreadContextComptime;
const CollisionHandler      = @import("collision-handler.zig").CollisionHandler;
const Mesh                  = @import("mesh.zig").Mesh;
const Node                  = @import("node.zig").Node;
const ComputeWorldEntity    = @import("comp-world-entity.zig").ComputeWorldEntity;
const Ball                  = @import("ball.zig").Ball;
const Paddle                = @import("paddle.zig").Paddle;
const Score                 = @import("score.zig").Score;
const ControlIndicator      = @import("control-indicator.zig").ControlIndicator;
const CenterLine            = @import("center-line.zig").CenterLine;
const Player                = @import("player.zig").Player;
const Human                 = @import("human.zig").Human;
const AI                    = @import("ai.zig").AI;
const time                  = @import("time.zig");
const cfg                   = @import("config.zig");
const frameTiming           = @import("frame-timing.zig");

pub const GameLayer = struct {
    const GameContext = struct {
        paddles:        *[PlayerManager.PLAYER_COUNT]Paddle,
        ball:           *Ball,
        scores:         *[PlayerManager.PLAYER_COUNT]Score,
        indicators:     *[PlayerManager.PLAYER_COUNT][3]ControlIndicator,
        currDeltaTime:  f32,
        didBallRestart: bool,
    };

    const ParticleAndWorldEntityTypesAndLen = struct {
        sizeOfParticle:     usize,
        numOfParticles:     usize,
        sizeOfWorldEntity:  usize,
        numOfWorldEntities: usize,
    };

    worldEntityManager: WorldEntityManager = undefined,
    playerManager:      PlayerManager      = undefined,
    particleManager:    ParticleManager    = undefined,

    computeWorldEntities: [cfg.NUM_OF_THREADS][ComputeWorldEntity.NUM_OF_ENTITIES]ComputeWorldEntity = undefined,

    collisionHandler:         CollisionHandler = undefined,
    gameSettingsInputHandler: GameInputHandler = undefined,
    audioHandler:             AudioHandler = undefined,

    worldHeight: f32 = undefined,
    worldWidth:  f32 = undefined,

    gameLastTime:              f64                     = 0.0,
    gameCurrDeltaTime:         f32                     = 0.0,
    gamePrevDeltaTime:         f32                     = 0.0,
    accumulatedGameDeltaTime:  f32                     = 0.0,
    numOfGameLoopItterations:  f32                     = 0.0,
    gameAvgFrameTime:          std.atomic.Value(f32)   = std.atomic.Value(f32).init(0.0),
    gameCurrPreSyncFrameTime:  std.atomic.Value(f32)   = std.atomic.Value(f32).init(0.0),
    accumulatedGameDeltaTimes: [cfg.NUM_OF_THREADS]f32 = [_]f32{0.0} ** cfg.NUM_OF_THREADS,

    prng:      *const std.Random,
    allocator: *const std.mem.Allocator,

    pub fn initParticleManager(self: *GameLayer, ctxComptime: *const ThreadContextComptime) !void {
        self.particleManager = .{
            .particleSize       = self.worldHeight * 0.002,
            .prng               = self.prng,
        };

        var tmpParticles = [_]Particle{.{
            .currBoundingBox        = ParticleBoundingBox.init(.{0.0, 0.0}, self.particleManager.particleSize),
            .prevBoundingBox        = ParticleBoundingBox.init(.{0.0, 0.0}, self.particleManager.particleSize),
            .color                  = .{1.0, 1.0, 1.0, 0.0},
            .position               = .{0.0, 0.0},
            .currVelocity           = .{0.0, 0.0},
            .prevVelocityDeltaTimed = .{0.0, 0.0},
            .size                   = self.particleManager.particleSize,
        }} ** ParticleManager.PARTICLE_COUNT;

        try ctxComptime.graphicsApiRelated.initParticlesResources(
            ctxComptime.graphicsApiRelated.graphicsAPI,
            @ptrCast(&tmpParticles),
            @sizeOf(Particle),
        );
    }

    fn initComputeWorldEntities(self: *GameLayer, ctxComptime: *const ThreadContextComptime) !void {
        const epsilon     = self.collisionHandler.epsilon;
        const currBall    = &self.worldEntityManager.underlyingBall;
        const currPaddles = &self.worldEntityManager.underlyingPaddles;

        const tmpEntities = [_]ComputeWorldEntity{
            .{
                .currBoundingBox  = currBall.currBoundingBox.getShavedOffBy(epsilon),
                .prevBoundingBox  = currBall.prevBoundingBox.getShavedOffBy(epsilon),
                .currVelocity     = currBall.currVelocity,
                .prevVelocity     = currBall.prevVelocity,
                .prevPrevVelocity = currBall.prevVelocity,
            },
            .{
                .currBoundingBox  = currPaddles[0].currBoundingBox.getShavedOffBy(epsilon),
                .prevBoundingBox  = currPaddles[0].prevBoundingBox.getShavedOffBy(epsilon),
                .currVelocity     = currPaddles[0].currVelocity,
                .prevVelocity     = currPaddles[0].prevVelocity,
                .prevPrevVelocity = currPaddles[0].prevVelocity,
            },
            .{
                .currBoundingBox  = currPaddles[1].currBoundingBox.getShavedOffBy(epsilon),
                .prevBoundingBox  = currPaddles[1].prevBoundingBox.getShavedOffBy(epsilon),
                .currVelocity     = currPaddles[1].currVelocity,
                .prevVelocity     = currPaddles[1].prevVelocity,
                .prevPrevVelocity = currPaddles[1].prevVelocity,
            }
        };

        for (&self.computeWorldEntities) |*entities| {
            entities.* = tmpEntities;
        }

        try ctxComptime.graphicsApiRelated.submitComputeWorldEntities(ctxComptime.graphicsApiRelated.graphicsAPI, @ptrCast(&tmpEntities));
    }

    fn initAudioHandler(self: *GameLayer) !void {
        self.audioHandler = .{
            .device = undefined,
            .state  = .{
                .bouncePieces = [_]AudioHandler.BouncePiece{.{
                    .note     = .{
                        .timerStart = 0.1,
                        .timerCurr  = 0.0,
                        .phase      = 0.0,
                        .basePitch  = 400.0,
                    },
                    .velocity = .{0.0, 0.0},
                }} ** AudioHandler.NUM_OF_BOUNCE_PIECES,
                .victoryPiece = .{
                    .notes = .{
                        .{
                            .timerStart = 0.2,
                            .timerCurr  = 0.0,
                            .phase      = 0.0,
                            .basePitch  = 650.0,
                        },
                        .{
                            .timerStart = 1.8,
                            .timerCurr  = 0.0,
                            .phase      = 0.0,
                            .basePitch  = 700.0,
                        },
                    },
                    .velocity = .{0.0, 0.0},
                },
                .goalPiece = .{
                    .note     = .{
                        .timerStart = 0.5,
                        .timerCurr  = 0.0,
                        .phase      = 0.0,
                        .basePitch  = 400.0,
                    },
                    .velocity = .{0.0, 0.0},
                },
            },
        };
    }


    pub fn initGameLogic(
        self:          *GameLayer,
        ctx:           *ThreadContextRuntime,
        ctxComptime:   *const ThreadContextComptime,
        currGameIndex: usize
    ) !ParticleAndWorldEntityTypesAndLen {
        self.worldHeight = cfg.WORLD_HEIGHT;
        self.worldWidth  = cfg.WORLD_HEIGHT * ctx.aspectRatio;

        try self.initParticleManager(ctxComptime);
        try self.initComputeWorldEntities(ctxComptime);

        self.initCollisionHandler();
        try self.initAudioHandler();
        self.initInputHandlerRelatedObjects(ctx);
        try self.loadGameEntities(ctxComptime);

        const t = time.getTimeInSeconds();
        self.gameLastTime                                            = t;
        self.worldEntityManager.ball[currGameIndex].timeTillMovement = t + 0.5;

        return .{
            .sizeOfParticle     = @sizeOf(Particle),
            .numOfParticles     = ParticleManager.PARTICLE_COUNT,
            .sizeOfWorldEntity  = @sizeOf(ComputeWorldEntity),
            .numOfWorldEntities = ComputeWorldEntity.NUM_OF_ENTITIES,
        };
    }

    fn initInputHandlerRelatedObjects(self: *GameLayer, ctx: *ThreadContextRuntime) void {
        self.initSettingsInputHandler(ctx);
        self.initPlayerManager(ctx);
    }

    fn initPlayerManager(self: *GameLayer, ctx: *ThreadContextRuntime) void {
        const KEY = @TypeOf(ctx.appInputHandler.*).KEY;

        const keys = [_][]const c_int{
            &.{KEY.W.asInt(),  KEY.S.asInt()},
            &.{},
            &.{},
            &.{KEY.UP.asInt(), KEY.DOWN.asInt()},
            &.{},
            &.{},
        };
        const inputHandlers = [_]GameInputHandler{
            GameInputHandler{.inputHandler = ctx.appInputHandler, .keys = keys[0]},
            GameInputHandler{.inputHandler = ctx.appInputHandler, .keys = keys[1]},
            GameInputHandler{.inputHandler = ctx.appInputHandler, .keys = keys[2]},
            GameInputHandler{.inputHandler = ctx.appInputHandler, .keys = keys[3]},
            GameInputHandler{.inputHandler = ctx.appInputHandler, .keys = keys[4]},
            GameInputHandler{.inputHandler = ctx.appInputHandler, .keys = keys[5]},
        };

        self.playerManager = .{
            .players = .{
                Player{.human = Human{.inputHandler = inputHandlers[0]}},
                Player{.ai    = AI.init(inputHandlers[1], self.worldHeight, self.prng, .CONSTRAINED, 150.0)},
                Player{.ai    = AI.init(inputHandlers[2], self.worldHeight, self.prng, .UNCONSTRAINED, 0.0)},
                Player{.human = Human{.inputHandler = inputHandlers[3]}},
                Player{.ai    = AI.init(inputHandlers[4], self.worldHeight, self.prng, .CONSTRAINED, 150.0)},
                Player{.ai    = AI.init(inputHandlers[5], self.worldHeight, self.prng, .UNCONSTRAINED, 0.0)},
            },
            .playerOne = undefined,
            .playerTwo = undefined,
        };
        self.playerManager.playerOne = &self.playerManager.players[0];
        self.playerManager.playerTwo = &self.playerManager.players[3];
    }

    fn initSettingsInputHandler(self: *GameLayer, ctx: *ThreadContextRuntime) void {
        const KEY = @TypeOf(ctx.appInputHandler.*).KEY;

        self.gameSettingsInputHandler = .{
            .inputHandler = ctx.appInputHandler,
            .keys         = &.{KEY.A.asInt(), KEY.RIGHT.asInt()},
        };
    }


    fn initCollisionHandler(self: *GameLayer) void {
        const epsilon = self.particleManager.particleSize + cfg.GENERAL_PURPOSE_EPSILON / 2.0;

        self.collisionHandler = .{
            .worldBoundingBox = BoundingBox.init(.{0.0, 0.0}, self.worldWidth, self.worldHeight, -epsilon),
            .epsilon          = epsilon,
        };
    }

    pub fn cleanup(self: *GameLayer, ctx: *const ThreadContextComptime) !void {
        self.particleManager.deinit(ctx);

        self.worldEntityManager.deinit(ctx);
    }

    pub fn updateForNewViewport(self: *GameLayer, ctx: *ThreadContextRuntime) !void {
        self.worldWidth = cfg.WORLD_HEIGHT * ctx.aspectRatio;

        for (&self.worldEntityManager.paddles) |*paddles| {
            self.updatePaddlePositions(paddles);
        }

        for (&self.worldEntityManager.centerLine) |*centerLine| {
            self.updateCenterLinePosition(centerLine);
        }

        const anyPaddle = &self.worldEntityManager.underlyingPaddles[0];
        for (&self.worldEntityManager.indicators) |*indicator| {
            self.updateControlIndicatorPositions(indicator, anyPaddle.node.width, anyPaddle.node.height);
        }

        for (&self.worldEntityManager.scores) |*scores| {
            self.updateScorePositions(scores);
        }

        self.updateBallSpeed(ctx);

        // NOTE: There is no practical need to update the size of the currently alive particles because they are short-lived.
        //  Otherwise, you would be updating maxNumOfParticles * numOfThreads without any practical reason. (2025-11-20)
        self.updateParticleSize();

        self.updateCollisionHandler();

        self.playerManager.playerOne.forceAction();
        self.playerManager.playerTwo.forceAction();
    }

    pub fn run(
        self:        *GameLayer,
        threadCtx:   *ThreadContextRuntime,
        ctxComptime: *const ThreadContextComptime
    ) !void {
        var gameCtx: GameContext = .{
            .paddles        = &self.worldEntityManager.paddles[0],
            .ball           = &self.worldEntityManager.ball[0],
            .scores         = &self.worldEntityManager.scores[0],
            .indicators     = &self.worldEntityManager.indicators[0],
            .currDeltaTime  = self.gameCurrDeltaTime,
            .didBallRestart = false,
        };

        while (!threadCtx.shouldClose.load(.acquire)) {
            std.Thread.sleep(10 * std.time.ns_per_us);

            if (threadCtx.shouldRecreateSwapchain.load(.acquire)) {
                _ = threadCtx.numOfWaitingThreads.fetchAdd(1, .acq_rel);
                while (threadCtx.shouldRecreateSwapchain.load(.acquire)) {
                    std.Thread.sleep(10 * std.time.ns_per_us);
                }
                _ = threadCtx.numOfWaitingThreads.fetchSub(1, .acq_rel);
            }

            var currTime            = time.getTimeInSeconds();
            defer self.gameLastTime = currTime;
            var currDeltaTime: f32  = blk: {
                const pureDeltaTime: f32 = @floatCast(currTime - self.gameLastTime);

                self.gameCurrPreSyncFrameTime.store(pureDeltaTime, .release);
                break :blk pureDeltaTime;
            };

            const syncWaitTime = threadCtx.gameLayerSyncWaitTimeNs.load(.acquire);
            if (syncWaitTime > 0.0) {
                threadCtx.gameLayerSyncWaitTimeNs.store(0.0, .release);
                std.Thread.sleep(syncWaitTime);

                currTime      = time.getTimeInSeconds();
                currDeltaTime = @floatCast(currTime - self.gameLastTime);
            }

            const currGameIndex     = threadCtx.threadStates.currGameIndex.load(.acquire);
            const nextGameIndex     = (currGameIndex + 1) % cfg.NUM_OF_THREADS;
            const nextNextGameIndex = (currGameIndex + 2) % cfg.NUM_OF_THREADS;

            self.gamePrevDeltaTime = self.gameCurrDeltaTime;
            self.gameCurrDeltaTime = currDeltaTime;
            self.accumulatedGameDeltaTimes[currGameIndex] += currDeltaTime;

            gameCtx.currDeltaTime = currDeltaTime;

            self.handleInputs(threadCtx, &gameCtx);
            try self.runPhysics(&gameCtx);
            try self.dealWithGameState(&gameCtx);

            if (gameCtx.didBallRestart) {
                self.updateSnapshotCurrFields(&gameCtx, currGameIndex);
                self.setSnapshot(currGameIndex, currGameIndex);
                gameCtx.didBallRestart = false;
            }

            if (threadCtx.threadStates.states[nextGameIndex].load(.acquire) == .GAME
                    and threadCtx.threadStates.states[nextNextGameIndex].load(.acquire) != .COMPUTE
                    and threadCtx.threadStates.states[nextNextGameIndex].load(.acquire) != .RENDER) {
                self.updateSnapshotCurrFields(&gameCtx, currGameIndex);
                try ctxComptime.graphicsApiRelated.updateComputeWorldEntities(
                    ctxComptime.graphicsApiRelated.graphicsAPI,
                    currGameIndex,
                    @ptrCast(&self.computeWorldEntities[currGameIndex]),
                );

                ctxComptime.graphicsApiRelated.waitUntilComputeIndexIsAvailable(ctxComptime.graphicsApiRelated.graphicsAPI, nextGameIndex);
                ctxComptime.graphicsApiRelated.waitUntilComputeIndexIsAvailable(ctxComptime.graphicsApiRelated.graphicsAPI, nextNextGameIndex);
                ctxComptime.graphicsApiRelated.waitUntilRenderIndexIsAvailable(ctxComptime.graphicsApiRelated.graphicsAPI, nextNextGameIndex);

                self.particleManager.spawnScheduledParticles(currGameIndex, ctxComptime);

                self.setSnapshot(nextGameIndex, currGameIndex);

                const prevGameIndex:     usize = @intCast(@mod(@as(isize, @intCast(currGameIndex)) - 1, cfg.NUM_OF_THREADS));
                const prevPrevGameIndex: usize = @intCast(@mod(@as(isize, @intCast(currGameIndex)) - 2, cfg.NUM_OF_THREADS));
                threadCtx.accumulatedGameDeltaTimesSnapshot[currGameIndex][0].store(self.accumulatedGameDeltaTimes[prevPrevGameIndex], .release);
                threadCtx.accumulatedGameDeltaTimesSnapshot[currGameIndex][1].store(self.accumulatedGameDeltaTimes[prevGameIndex], .release);
                threadCtx.accumulatedGameDeltaTimesSnapshot[currGameIndex][2].store(self.accumulatedGameDeltaTimes[currGameIndex], .release);

                self.accumulatedGameDeltaTimes[nextGameIndex] = 0.0;

                gameCtx.ball       = &self.worldEntityManager.ball[nextGameIndex];
                gameCtx.paddles    = &self.worldEntityManager.paddles[nextGameIndex];
                gameCtx.scores     = &self.worldEntityManager.scores[nextGameIndex];
                gameCtx.indicators = &self.worldEntityManager.indicators[nextGameIndex];
                gameCtx.ball.*     = self.worldEntityManager.ball[currGameIndex];
                @memcpy(gameCtx.paddles, &self.worldEntityManager.paddles[currGameIndex]);
                @memcpy(gameCtx.scores, &self.worldEntityManager.scores[currGameIndex]);
                @memcpy(gameCtx.indicators, &self.worldEntityManager.indicators[currGameIndex]);

                threadCtx.threadStates.currGameIndex.store(nextGameIndex, .release);
                threadCtx.threadStates.states[currGameIndex].store(.COMPUTE, .release);
            }

            frameTiming.updateFrameTime(currDeltaTime, &self.accumulatedGameDeltaTime, &self.numOfGameLoopItterations, &self.gameAvgFrameTime);
            //if (self.accumulatedGameDeltaTime == 0.0) {
            //    frameTiming.showFrameTime("Game", self.gameAvgFrameTime.load(.acquire));
            //}
        }
    }

    fn handleInputs(
        self:      *GameLayer,
        threadCtx: *ThreadContextRuntime,
        gameCtx:   *GameContext
    ) void {
        self.handleGameSettingsInputs(threadCtx, gameCtx);
        self.handlePlayerInputs(gameCtx);
    }

    fn handleGameSettingsInputs(
        self:      *GameLayer,
        threadCtx: *ThreadContextRuntime,
        gameCtx:   *GameContext
    ) void {
        const KEY = @TypeOf(threadCtx.appInputHandler.*).KEY;

        if (self.gameSettingsInputHandler.isKeyClicked(KEY.A.asInt())) {
            gameCtx.indicators[0][2].flip();
            self.playerManager.flipPlayerOne();
        }

        if (self.gameSettingsInputHandler.isKeyClicked(KEY.RIGHT.asInt())) {
            gameCtx.indicators[1][2].flip();
            self.playerManager.flipPlayerTwo();
        }

        self.gameSettingsInputHandler.cleanKeys();
    }

    fn handlePlayerInputs(self: *GameLayer, ctx: *GameContext) void {
        self.handlePlayerOneInput(ctx);
        self.handlePlayerTwoInput(ctx);
    }

    fn handlePlayerOneInput(self: *GameLayer, ctx: *GameContext) void {
        const worldBoundingBox = self.collisionHandler.worldBoundingBox;
        const paddleInfo: Player.GameEntityInfo = .{
            .currBoundingBox = ctx.paddles[0].currBoundingBox,
            .currVelocity    = ctx.paddles[0].currVelocity,
            .centerY         = ctx.paddles[0].node.getCenter()[1],
        };
        const ballInfo: Player.GameEntityInfo = .{
            .currBoundingBox = ctx.ball.currBoundingBox,
            .currVelocity    = ctx.ball.currVelocity,
            .centerY         = ctx.ball.node.getCenter()[1],
        };

        self.playerManager.playerOne.takeAction(&paddleInfo, &ballInfo, worldBoundingBox);

        var velY: f32 = 0.0;

        if (self.playerManager.playerOne.doesGoUp()) {
            velY += ctx.paddles[0].speed;
            ctx.indicators[0][0].flipOn();
        } else {
            ctx.indicators[0][0].flipOff();
        }

        if (self.playerManager.playerOne.doesGoDown()) {
            velY -= ctx.paddles[0].speed;
            ctx.indicators[0][1].flipOn();
        } else {
            ctx.indicators[0][1].flipOff();
        }

        ctx.paddles[0].setVelocityYTo(velY);

        self.playerManager.playerOne.getInputHandler().cleanKeys();
    }

    fn handlePlayerTwoInput(self: *GameLayer, ctx: *GameContext) void {
        const worldBoundingBox = self.collisionHandler.worldBoundingBox;
        const paddleInfo: Player.GameEntityInfo = .{
            .currBoundingBox = ctx.paddles[1].currBoundingBox,
            .currVelocity    = ctx.paddles[1].currVelocity,
            .centerY         = ctx.paddles[1].node.getCenter()[1],
        };
        const ballInfo: Player.GameEntityInfo = .{
            .currBoundingBox = ctx.ball.currBoundingBox,
            .currVelocity    = ctx.ball.currVelocity,
            .centerY         = ctx.ball.node.getCenter()[1],
        };

        self.playerManager.playerTwo.takeAction(&paddleInfo, &ballInfo, worldBoundingBox);
        var velY: f32 = 0.0;

        if (self.playerManager.playerTwo.doesGoUp()) {
            velY += ctx.paddles[1].speed;
            ctx.indicators[1][0].flipOn();
        } else {
            ctx.indicators[1][0].flipOff();
        }

        if (self.playerManager.playerTwo.doesGoDown()) {
            velY -= ctx.paddles[1].speed;
            ctx.indicators[1][1].flipOn();
        } else {
            ctx.indicators[1][1].flipOff();
        }

        ctx.paddles[1].setVelocityYTo(velY);

        self.playerManager.playerTwo.getInputHandler().cleanKeys();
    }

    fn runPhysics(self: *GameLayer, ctx: *GameContext) !void {
        handleMovements(ctx);
        try self.handleCollisions(ctx);
    }

    fn handleMovements(ctx: *GameContext) void {
        for (ctx.paddles) |*paddle| {
            handlePaddleMovement(paddle, ctx.currDeltaTime);
        }
        handleBallMovement(ctx.ball, ctx.currDeltaTime);
    }

    fn handleCollisions(self: *GameLayer, ctx: *GameContext) !void {
        for (ctx.paddles) |*paddle| {
            self.handlePaddleCollision(paddle);
        }
        try self.handleBallCollision(ctx);
    }

    fn handlePaddleMovement(paddle: *Paddle, currDeltaTime: f32) void {
        var velocityDeltaTimed: cglm.vec2 = undefined;
        cglm.glm_vec2_scale(&paddle.currVelocity, currDeltaTime, &velocityDeltaTimed);
        paddle.moveBy(velocityDeltaTimed);
    }

    fn handleBallMovement(ball: *Ball, currDeltaTime: f32) void {
        if (!ball.canMove()) {
            return;
        }

        var ballVelocityDeltaTimed: cglm.vec2 = undefined;
        cglm.glm_vec2_scale(&ball.currVelocity, currDeltaTime, &ballVelocityDeltaTimed);
        ball.moveBy(ballVelocityDeltaTimed);
    }

    fn handlePaddleCollision(self: *GameLayer, paddle: *Paddle) void {
        const worldBoundingBox = self.collisionHandler.worldBoundingBox;

        if (paddle.currBoundingBox.maxY >= worldBoundingBox.maxY) {
            paddle.setTranslation(
                .{
                    paddle.node.translation[0],
                    worldBoundingBox.maxY - (paddle.currBoundingBox.maxY - paddle.node.translation[1]),
                },
                self.collisionHandler.epsilon,
            );
        } else if (paddle.currBoundingBox.minY <= worldBoundingBox.minY) {
            paddle.setTranslation(
                .{
                    paddle.node.translation[0],
                    worldBoundingBox.minY + (paddle.node.translation[1] - paddle.currBoundingBox.minY),
                },
                self.collisionHandler.epsilon,
            );
        }
    }

    fn handleBallCollision(self: *GameLayer, ctx: *GameContext) !void {
        const worldBoundingBox = self.collisionHandler.worldBoundingBox;
        const epsilon          = self.collisionHandler.epsilon;
        const ball             = ctx.ball;

        var newBallVelocity = ball.currVelocity;

        if (ball.currBoundingBox.maxY >= worldBoundingBox.maxY) {
            const penetrationDistance             = ball.currBoundingBox.maxY - worldBoundingBox.maxY;
            const ballDistFromPureOriginYToBBMaxY = ball.currBoundingBox.maxY - ball.node.translation[1];
            ball.setTranslation(
                .{
                    ball.node.translation[0],
                    worldBoundingBox.maxY - ballDistFromPureOriginYToBBMaxY - penetrationDistance,
                },
                self.collisionHandler.epsilon,
            );

            try self.particleManager.scheduleParticlesBounce(ball, .UP, epsilon, 0.0);

            newBallVelocity[1] *= -1;

            self.audioHandler.playBounce(ball.prevVelocity);
        } else if (ball.currBoundingBox.minY <= worldBoundingBox.minY) {
            const penetrationDistance             = worldBoundingBox.minY - ball.currBoundingBox.minY;
            const ballDistFromPureOriginYToBBMinY = ball.node.translation[1] - ball.currBoundingBox.minY;
            ball.setTranslation(
                .{
                    ball.node.translation[0],
                    worldBoundingBox.minY + ballDistFromPureOriginYToBBMinY + penetrationDistance,
                },
                self.collisionHandler.epsilon,
            );

            try self.particleManager.scheduleParticlesBounce(ball, .DOWN, epsilon, 0.0);

            newBallVelocity[1] *= -1;

            self.audioHandler.playBounce(ball.prevVelocity);
        }

        // NOTE: This for loop will not change the ball's velocity. That change happens at the end of this method.
        //  Which means that this wouldn't work well if the ball could actually collide with both paddles
        //  in the same frame, but this case will never happen in this Pong game. (2026-01-19)
        for (ctx.paddles) |*paddle| {
            const ballSweptBroadPhaseBox   = ball.prevBoundingBox.getSweptBoundingBoxFromBB(&ball.currBoundingBox);
            const paddleSweptBroadPhaseBox = paddle.prevBoundingBox.getSweptBoundingBoxFromBB(&paddle.currBoundingBox);
            if (!CollisionHandler.doCollide(ballSweptBroadPhaseBox, paddleSweptBroadPhaseBox)) {
                continue;
            }

            const ballPrevSweptBroadPhaseBox   = ball.prevBoundingBox.getSweptBoundingBoxFromVel(.{
                -ball.prevVelocity[0] * self.gamePrevDeltaTime,
                -ball.prevVelocity[1] * self.gamePrevDeltaTime
            });
            const paddlePrevSweptBroadPhaseBox = paddle.prevBoundingBox.getSweptBoundingBoxFromVel(.{
                -paddle.prevVelocity[0] * self.gamePrevDeltaTime,
                -paddle.prevVelocity[1] * self.gamePrevDeltaTime
            });
            if (CollisionHandler.doCollide(ballPrevSweptBroadPhaseBox, paddlePrevSweptBroadPhaseBox)) {
                continue;
            }

            // NOTE: Using a broadphase box directly in the Swept AABB algorithm instead of using a bounding box enables
            //  the ball to be continuously pushed. (2025-10-28)
            // NOTE: One of the edge cases that can happen is that sweptAABB can confuse the penetration direction
            //  of the ball if it moves fast enough and if it hits the top or the bottom of the paddle closer to the edge.
            //  But the actual velocity of the ball stays correct because it doesn't directly depend on the sweptAABB algorithm's result. (2026-1-19)
            const res = CollisionHandler.sweptAABB(ballSweptBroadPhaseBox, paddleSweptBroadPhaseBox, ball.currVelocity, paddle.currVelocity);

            const paddleCenterPos = paddle.node.getCenter();
            // This makes the ball move faster the more the collision is off the center of the paddle which makes
            //  the game more exciting compared to the original pong in which the ball always(?) moves at the same speed.
            const intersectY     = ball.node.getCenter()[1] - paddleCenterPos[1];
            const normIntersectY = intersectY * (2.0 / paddle.node.height);
            // This is an artificial change to the ball's velocity.x direction so that it doesn't
            //  accidentally bounce back to its previous direction when the paddle touches or pushes it vertically.
            const velXDir   = std.math.sign(self.worldWidth / 2 - paddleCenterPos[0]);
            newBallVelocity = .{
                ball.speed * velXDir,
                ball.speed * normIntersectY,
            };

            ball.correctThePosition(.{
                (@abs((newBallVelocity[0] + paddle.currVelocity[0]) * res.collisionTime) + cfg.GENERAL_PURPOSE_EPSILON) * res.normalX,
                (@abs((newBallVelocity[1] + paddle.currVelocity[1]) * res.collisionTime) + cfg.GENERAL_PURPOSE_EPSILON) * res.normalY
            });

            // The side that gets passed to scheduleParticlesBounce will be the collision side of the ball and not that of the paddle.
            if (res.normalY == -1.0) {
                try self.particleManager.scheduleParticlesBounce(ball, .UP, epsilon, cfg.GENERAL_PURPOSE_EPSILON);
            } else if (res.normalY == 1.0) {
                try self.particleManager.scheduleParticlesBounce(ball, .DOWN, epsilon, cfg.GENERAL_PURPOSE_EPSILON);
            } else if (res.normalX == -1.0) {
                try self.particleManager.scheduleParticlesBounce(ball, .RIGHT, epsilon, cfg.GENERAL_PURPOSE_EPSILON);
            } else if (res.normalX == 1.0) {
                try self.particleManager.scheduleParticlesBounce(ball, .LEFT, epsilon, cfg.GENERAL_PURPOSE_EPSILON);
            }

            self.audioHandler.playBounce(ball.prevVelocity);
        }

        ball.setVelocityTo(newBallVelocity);
    }

    fn dealWithGameState(self: *GameLayer, ctx: *GameContext) !void {
        const worldBoundingBox = self.collisionHandler.worldBoundingBox;
        const epsilon          = self.collisionHandler.epsilon;

        if (ctx.ball.currBoundingBox.minX <= worldBoundingBox.minX) {
            ctx.ball.setTranslation(
                .{
                    worldBoundingBox.minX + (ctx.ball.node.translation[0] - ctx.ball.currBoundingBox.minX),
                    ctx.ball.node.translation[1],
                },
                self.collisionHandler.epsilon,
            );

            try self.particleManager.scheduleParticlesGoal(ctx.ball, .LEFT, epsilon);

            ctx.scores[1].increment();
            ctx.ball.doRestart = true;

            self.audioHandler.playGoal(ctx.ball.currVelocity);
        } else if (ctx.ball.currBoundingBox.maxX >= worldBoundingBox.maxX) {
            ctx.ball.setTranslation(
                .{
                    worldBoundingBox.maxX - (ctx.ball.currBoundingBox.maxX - ctx.ball.node.translation[0]),
                    ctx.ball.node.translation[1],
                },
                self.collisionHandler.epsilon,
            );

            try self.particleManager.scheduleParticlesGoal(ctx.ball, .RIGHT, epsilon);

            ctx.scores[0].increment();
            ctx.ball.doRestart = true;

            self.audioHandler.playGoal(ctx.ball.currVelocity);
        }

        if (ctx.ball.doRestart) {
            try self.resetScoresIfWrapped(ctx);
            self.restartBall(ctx.ball);
            ctx.didBallRestart = true;
        }

        for (ctx.paddles) |*paddle| {
            if (paddle.hasWon) {
                paddle.hasWon = false;
                for (ctx.scores) |*score| {
                    score.setToZero();
                }

                break;
            }
        }
    }

    fn restartBall(self: *GameLayer, ball: *Ball) void {
        const ballPosY = @as(f32, @floatFromInt((self.prng.intRangeAtMost(i8, 0, 80) - 40))) / 100.0;
        ball.setTranslation(
            .{
                self.worldWidth / 2 - ball.node.width / 2.0,
                self.worldHeight * (0.5 + ballPosY) - ball.node.height * 0.5
            },
            self.collisionHandler.epsilon,
        );

        const dirX: f32 = @floatFromInt(self.prng.intRangeAtMost(i8, 0, 1) * 2 - 1);
        const dirY      = @as(f32, @floatFromInt(self.prng.intRangeAtMost(i8, -90, 90))) / 100;
        ball.setVelocityTo(.{
            ball.speed / 2 * dirX,
            ball.speed / 2 * dirY
        });

        // When the ball restarts, these fields have to not point to the their last values from before the ball restart.
        ball.prevTranslation = ball.node.translation;
        ball.prevVelocity    = ball.currVelocity;
        ball.prevBoundingBox = ball.currBoundingBox;

        ball.timeTillMovement = time.getTimeInSeconds() + 0.5;
        ball.doRestart        = false;
    }

    fn resetScoresIfWrapped(self: *GameLayer, ctx: *GameContext) !void {
        outer: for (0..ctx.scores.len) |i| {
            if (ctx.scores[i].didWrap) {
                if (ctx.scores[i].nodes[0].translation[0] > self.collisionHandler.worldBoundingBox.getCenterX()) {
                    try self.particleManager.scheduleParticlesVictory(ctx.ball, .LEFT, self.collisionHandler.worldBoundingBox);
                } else {
                    try self.particleManager.scheduleParticlesVictory(ctx.ball, .RIGHT, self.collisionHandler.worldBoundingBox);
                }

                ctx.scores[i].reset();
                ctx.scores[(i + 1) % ctx.scores.len].reset();

                self.audioHandler.playVictory(ctx.ball.prevVelocity);

                break :outer;
            }
        }
    }

    fn setSnapshot(
        self:          *GameLayer,
        currGameIndex: usize,
        prevGameIndex: usize,
    ) void {
        const currComputeWorldEntities = &self.computeWorldEntities[currGameIndex];
        const prevComputeWorldEntities = &self.computeWorldEntities[prevGameIndex];

        currComputeWorldEntities[0] = .{
            .currBoundingBox  = prevComputeWorldEntities[0].currBoundingBox,
            .prevBoundingBox  = prevComputeWorldEntities[0].currBoundingBox,
            .currVelocity     = prevComputeWorldEntities[0].currVelocity,
            .prevVelocity     = prevComputeWorldEntities[0].currVelocity,
            .prevPrevVelocity = prevComputeWorldEntities[0].prevVelocity,
        };

        for (1..self.worldEntityManager.underlyingPaddles.len + 1) |i| {
            currComputeWorldEntities[i] = .{
                .currBoundingBox  = prevComputeWorldEntities[i].currBoundingBox,
                .prevBoundingBox  = prevComputeWorldEntities[i].currBoundingBox,
                .currVelocity     = prevComputeWorldEntities[i].currVelocity,
                .prevVelocity     = prevComputeWorldEntities[i].currVelocity,
                .prevPrevVelocity = prevComputeWorldEntities[i].prevVelocity,
            };
        }
    }

    fn updateSnapshotCurrFields(
        self:          *GameLayer,
        ctx:           *GameContext,
        currGameIndex: usize,
    ) void {
        const epsilon                  = self.collisionHandler.epsilon;
        const currComputeWorldEntities = &self.computeWorldEntities[currGameIndex];

        if (ctx.ball.isDirty) {
            currComputeWorldEntities[0].currBoundingBox = ctx.ball.currBoundingBox.getShavedOffBy(epsilon);
            currComputeWorldEntities[0].currVelocity    = ctx.ball.currVelocity;
            ctx.ball.isDirty = false;
        }

        for (ctx.paddles, 1..) |*paddle, i| {
            if (paddle.isDirty) {
                currComputeWorldEntities[i].currBoundingBox = paddle.currBoundingBox.getShavedOffBy(epsilon);
                currComputeWorldEntities[i].currVelocity    = paddle.currVelocity;
                paddle.isDirty = false;
            }
        }
    }

    fn loadGameEntities(self: *GameLayer, ctxComptime: *const ThreadContextComptime) !void {
        try self.loadBall(&self.worldEntityManager.underlyingBall);
        try self.loadPaddles(&self.worldEntityManager.underlyingPaddles);
        try self.loadCenterLine(&self.worldEntityManager.underlyingCenterLine);
        try self.loadScores(&self.worldEntityManager.underlyingScores);

        const anyPaddle = &self.worldEntityManager.underlyingPaddles[0];
        try self.loadControlIndicators(&self.worldEntityManager.underlyingIndicators, anyPaddle.node.width, anyPaddle.node.height);

        for (0..WorldEntityManager.NUM_OF_STATES) |i| {
            @memcpy(&self.worldEntityManager.paddles[i], &self.worldEntityManager.underlyingPaddles);
            @memcpy(&self.worldEntityManager.scores[i], &self.worldEntityManager.underlyingScores);
            @memcpy(&self.worldEntityManager.indicators[i], &self.worldEntityManager.underlyingIndicators);
            self.worldEntityManager.ball[i]       = self.worldEntityManager.underlyingBall;
            self.worldEntityManager.centerLine[i] = self.worldEntityManager.underlyingCenterLine;
        }

        const paddleNumOfNodes:     usize = self.worldEntityManager.underlyingPaddles.len;
        const scoresNumOfNodes:     usize = self.worldEntityManager.underlyingScores.len * self.worldEntityManager.underlyingScores[0].nodes.len;
        const indicatorsNumOfNodes: usize = self.worldEntityManager.underlyingIndicators.len * self.worldEntityManager.underlyingIndicators[0].len;
        const ballNumOfNodes:       usize = 1;
        const centerLineNumOfNodes: usize = self.worldEntityManager.underlyingCenterLine.nodes.items.len;
        const batchSize = paddleNumOfNodes + scoresNumOfNodes + indicatorsNumOfNodes + ballNumOfNodes + centerLineNumOfNodes;
        var nodes = try std.ArrayList(*Node).initCapacity(self.allocator.*, batchSize * WorldEntityManager.NUM_OF_STATES);
        defer nodes.deinit(self.allocator.*);

        for (0..WorldEntityManager.NUM_OF_STATES) |i| {
            for (self.worldEntityManager.centerLine[i].nodes.items) |*node| {
                nodes.appendAssumeCapacity(node);
            }

            for (&self.worldEntityManager.paddles[i]) |*paddle| {
                nodes.appendAssumeCapacity(&paddle.node);
            }

            for (&self.worldEntityManager.scores[i]) |*score| {
                for (&score.nodes) |*node| {
                    nodes.appendAssumeCapacity(node);
                }
            }

            for (&self.worldEntityManager.indicators[i]) |*indicators| {
                for (indicators) |*indicator| {
                    nodes.appendAssumeCapacity(&indicator.node);
                }
            }

            nodes.appendAssumeCapacity(&self.worldEntityManager.ball[i].node);
        }

        try ctxComptime.graphicsApiRelated.initRenderWorldEntitiesResources(ctxComptime.graphicsApiRelated.graphicsAPI, nodes.items, batchSize);
    }

    fn loadBall(self: *GameLayer, ball: *Ball) !void {
        const ballHeight = self.worldHeight * 0.025;
        const ballWidth  = ballHeight;

        const depth           = 0.0;
        const opacity         = 0.8;
        const vertexPositions = [_]cglm.vec3{
            .{      0.0,        0.0, depth},
            .{ballWidth,        0.0, depth},
            .{ballWidth, ballHeight, depth},
            .{      0.0, ballHeight, depth},
        };
        const color           = [_]f32{1.0, 1.0, 1.0, opacity};
        const topology        = [_]u32{0, 1, 2, 2, 3, 0};
        const speed           = self.worldWidth * 0.8;

        ball.* = .{
            .node             = .{
                .mesh        = try Mesh.init(self.allocator),
                .height      = ballHeight,
                .width       = ballWidth,
                .translation = undefined,
                .depth       = depth,
                .opacity     = opacity,
            },
            .currBoundingBox  = undefined,
            .prevBoundingBox  = undefined,
            .prevTranslation  = undefined,
            .currVelocity     = .{speed / 2, 0.0},
            .prevVelocity     = .{speed / 2, 0.0},
            .speed            = speed,
            .timeTillMovement = 0.0,
            .doRestart        = false,
            .isDirty          = true,
        };

        for (vertexPositions) |pos| {
            try ball.node.mesh.appendVertex(.{
                .pos   = pos,
                .color = color,
            });
        }

        for (topology) |index| {
            try ball.node.mesh.appendIndex(index);
        }

        const translation: cglm.vec2 = .{
            self.worldWidth / 2.0 - ball.node.width / 2.0,
            self.worldHeight / 2.0 - ball.node.height / 2.0
        };
        ball.currBoundingBox = BoundingBox.init(translation, ballWidth, ballHeight, self.collisionHandler.epsilon);
        ball.setTranslation(
            translation,
            self.collisionHandler.epsilon,
        );
    }

    fn loadPaddles(self: *GameLayer, paddles: []Paddle) !void {
        const paddleWidth  = self.worldHeight * 0.025;
        const paddleHeight = self.worldHeight * 0.15;

        const depth        = 0.2;
        const opacity      = 0.8;
        const positions    = [_][]const cglm.vec3{&.{
            .{        0.0,          0.0, depth},
            .{paddleWidth,          0.0, depth},
            .{paddleWidth, paddleHeight, depth},
            .{        0.0, paddleHeight, depth},
        }} ** PlayerManager.PLAYER_COUNT;
        const colors       = [_]cglm.vec4{.{1.0, 1.0, 1.0, opacity}} ** PlayerManager.PLAYER_COUNT;
        const topology     = [_]u32{0, 1, 2, 2, 3, 0};

        for (paddles, 0..) |*paddle, i| {
            paddle.* = .{
                .node            = .{
                    .mesh        = try Mesh.init(self.allocator),
                    .width       = paddleWidth,
                    .height      = paddleHeight,
                    .translation = undefined,
                    .depth       = depth,
                    .opacity     = opacity,
                },
                .currBoundingBox = undefined,
                .prevBoundingBox = undefined,
                .prevTranslation = undefined,
                .currVelocity    = .{0.0, 0.0},
                .prevVelocity    = .{0.0, 0.0},
                .speed           = self.worldHeight * 0.7,
                .hasWon          = false,
                .isDirty         = true,
            };

            for (0..positions[i].len) |j| {
                try paddle.node.mesh.appendVertex(.{
                    .pos   = positions[i][j],
                    .color = colors[i],
                });
            }

            for (topology) |index| {
                try paddle.node.mesh.appendIndex(index);
            }
        }

        paddles[0].setTranslation(
            .{
                self.worldWidth * 0.05,
                self.worldHeight / 2.0 - paddles[0].node.height / 2.0,
            },
            self.collisionHandler.epsilon,
        );
        paddles[1].setTranslation(
            .{
                self.worldWidth * 0.95 - paddles[1].node.width,
                self.worldHeight / 2.0 - paddles[1].node.height / 2.0,
            },
            self.collisionHandler.epsilon,
        );
    }

    fn loadCenterLine(self: *GameLayer, centerLine: *CenterLine) !void {
        // These calculations are a bit expensive; but it's fine because it's done only once at startup, while being more readable.
        const numOfDots           = std.math.pow(f32, 3.0, 4.0);
        const centerLineDotHeight = self.worldHeight / numOfDots;
        const centerLineDotWidth  = centerLineDotHeight;

        const depth           = 0.9;
        const opacity         = 0.4;
        const vertexPositions = [_]cglm.vec3{
            .{               0.0,                 0.0, depth},
            .{centerLineDotWidth,                 0.0, depth},
            .{centerLineDotWidth, centerLineDotHeight, depth},
            .{               0.0, centerLineDotHeight, depth},
        };
        const color    = [_]f32{1.0, 1.0, 1.0, opacity};
        const topology = [_]u32{0, 1,  2,  2,  3, 0};

        const numOfDotsNeeded = @ceil(numOfDots / 2);
        centerLine.* = .{
            .nodes     = try std.ArrayList(Node).initCapacity(self.allocator.*, @intFromFloat(numOfDotsNeeded)),
            .allocator = self.allocator,
        };

        for (0..@intFromFloat(numOfDotsNeeded)) |i| {
            const translation = [_]f32{
                self.worldWidth / 2 - centerLineDotWidth / 2,
                @as(f32, @floatFromInt((i * 2))) * centerLineDotHeight
            };
            const node: Node = .{
                .mesh        = try Mesh.init(self.allocator),
                .width       = centerLineDotWidth,
                .height      = centerLineDotHeight,
                .translation = translation,
                .depth       = depth,
                .opacity     = opacity,
            };

            for (vertexPositions) |pos| {
                try node.mesh.appendVertex(.{
                    .pos   = pos,
                    .color = color,
                });
            }

            for (topology) |index| {
                try node.mesh.appendIndex(index);
            }

            try centerLine.addNode(node);
        }
    }

    fn loadScores(self: *GameLayer, scores: []Score) !void {
        const scoreWidth   = self.worldHeight * 0.05;
        const scoreLenUnit = scoreWidth / 4;
        const scoreHeight  = scoreWidth * 2 - scoreLenUnit;

        const depth           = 0.9;
        const opacity         = 0.4;
        const vertexPositions = [_][]const cglm.vec3{
            &.{
                .{       0.0,          0.0, depth},
                .{scoreWidth,          0.0, depth},
                .{scoreWidth, scoreLenUnit, depth},
                .{       0.0, scoreLenUnit, depth},
            },
            &.{
                .{         0.0,        0.0, depth},
                .{scoreLenUnit,        0.0, depth},
                .{scoreLenUnit, scoreWidth, depth},
                .{         0.0, scoreWidth, depth},
            },
        };
        const colors   = [_]cglm.vec4{.{1.0, 1.0, 1.0, opacity}} ** PlayerManager.PLAYER_COUNT;
        const topology = [_]u32{0, 1, 2, 2, 3, 0};

        for (scores, 0..) |*score, i| {
            score.* = .{
                .nodes     = undefined,
                .currDigit = 0,
                .didWrap   = false,
            };

            for (&score.nodes, 0..) |*node, j| {
                node.* = .{
                    .mesh        = try Mesh.init(self.allocator),
                    .width       = scoreWidth,
                    .height      = scoreHeight,
                    .translation = undefined,
                    .depth       = depth,
                    .opacity     = opacity,
                };

                const posIndex: usize = if (j % 3 == 0) 0 else 1;
                for (vertexPositions[posIndex]) |pos| {
                    try node.mesh.appendVertex(.{
                        .pos   = pos,
                        .color = colors[i],
                    });
                }

                for (topology) |index| {
                    try node.mesh.appendIndex(index);
                }
            }

            score.setToZero();
        }

        self.initializeScorePositions(scores);
    }

    fn loadControlIndicators(
        self:         *GameLayer,
        indicators:   *[PlayerManager.PLAYER_COUNT][3]ControlIndicator,
        paddleWidth:  f32,
        paddleHeight: f32,
    ) !void {
        const height  = self.worldHeight * 0.0425;
        const lenUnit = height / 7;
        const width   = lenUnit * 5;

        const depth           = 0.9;
        const opacity         = ControlIndicator.OFF;
        const vertexPositions = [_][]const []const cglm.vec3{
            &.{
                &.{
                    // W
                    .{lenUnit * 0, lenUnit * 7, depth},
                    .{lenUnit * 0, lenUnit * 1, depth},
                    .{lenUnit * 0, lenUnit * 0, depth},
                    .{lenUnit * 2, lenUnit * 0, depth},
                    .{lenUnit * 3, lenUnit * 0, depth},
                    .{lenUnit * 5, lenUnit * 0, depth},
                    .{lenUnit * 5, lenUnit * 1, depth},
                    .{lenUnit * 5, lenUnit * 7, depth},
                    .{lenUnit * 4, lenUnit * 7, depth},
                    .{lenUnit * 4, lenUnit * 1, depth},
                    .{lenUnit * 3, lenUnit * 1, depth},
                    .{lenUnit * 3, lenUnit * 4, depth},
                    .{lenUnit * 2, lenUnit * 4, depth},
                    .{lenUnit * 2, lenUnit * 1, depth},
                    .{lenUnit * 1, lenUnit * 1, depth},
                    .{lenUnit * 1, lenUnit * 7, depth},
                },
                &.{
                    // S
                    .{lenUnit * 5, lenUnit * 7, depth},
                    .{lenUnit * 1, lenUnit * 7, depth},
                    .{lenUnit * 0, lenUnit * 7, depth},
                    .{lenUnit * 0, lenUnit * 3, depth},
                    .{lenUnit * 1, lenUnit * 3, depth},
                    .{lenUnit * 4, lenUnit * 3, depth},
                    .{lenUnit * 4, lenUnit * 1, depth},
                    .{lenUnit * 0, lenUnit * 1, depth},
                    .{lenUnit * 0, lenUnit * 0, depth},
                    .{lenUnit * 4, lenUnit * 0, depth},
                    .{lenUnit * 5, lenUnit * 0, depth},
                    .{lenUnit * 5, lenUnit * 3, depth},
                    .{lenUnit * 5, lenUnit * 4, depth},
                    .{lenUnit * 1, lenUnit * 4, depth},
                    .{lenUnit * 1, lenUnit * 6, depth},
                    .{lenUnit * 5, lenUnit * 6, depth},
                },
                &.{
                    // A
                    .{lenUnit * 0, lenUnit * 0, depth},
                    .{lenUnit * 0, lenUnit * 7, depth},
                    .{lenUnit * 1, lenUnit * 7, depth},
                    .{lenUnit * 4, lenUnit * 7, depth},
                    .{lenUnit * 5, lenUnit * 7, depth},
                    .{lenUnit * 5, lenUnit * 0, depth},
                    .{lenUnit * 4, lenUnit * 0, depth},
                    .{lenUnit * 4, lenUnit * 3, depth},
                    .{lenUnit * 4, lenUnit * 4, depth},
                    .{lenUnit * 4, lenUnit * 6, depth},
                    .{lenUnit * 1, lenUnit * 6, depth},
                    .{lenUnit * 1, lenUnit * 4, depth},
                    .{lenUnit * 1, lenUnit * 3, depth},
                    .{lenUnit * 1, lenUnit * 0, depth},
                },
            },
            &.{
                &.{
                    // UP ARROW
                    .{lenUnit * 2, lenUnit * 0,    depth},
                    .{lenUnit * 2, lenUnit * 5.75, depth},
                    .{lenUnit * 0, lenUnit * 3.75, depth},
                    .{lenUnit * 0, lenUnit * 5,    depth},
                    .{lenUnit * 2, lenUnit * 7,    depth},
                    .{lenUnit * 3, lenUnit * 7,    depth},
                    .{lenUnit * 5, lenUnit * 5,    depth},
                    .{lenUnit * 5, lenUnit * 3.75, depth},
                    .{lenUnit * 3, lenUnit * 5.75, depth},
                    .{lenUnit * 3, lenUnit * 0,    depth},
                },
                &.{
                    // DOWN ARROW
                    .{lenUnit * 2, lenUnit * 0,    depth},
                    .{lenUnit * 3, lenUnit * 0,    depth},
                    .{lenUnit * 5, lenUnit * 2,    depth},
                    .{lenUnit * 5, lenUnit * 3.25, depth},
                    .{lenUnit * 3, lenUnit * 1.25, depth},
                    .{lenUnit * 3, lenUnit * 7,    depth},
                    .{lenUnit * 2, lenUnit * 7,    depth},
                    .{lenUnit * 2, lenUnit * 1.25, depth},
                    .{lenUnit * 0, lenUnit * 3.25, depth},
                    .{lenUnit * 0, lenUnit * 2,    depth},
                },
                &.{
                    // RIGHT ARROW
                    .{lenUnit * 0,    lenUnit * 2,  depth},
                    .{lenUnit * 5.75, lenUnit * 2,  depth},
                    .{lenUnit * 3.75, lenUnit * 0,  depth},
                    .{lenUnit * 5,    lenUnit * 0,  depth},
                    .{lenUnit * 7,    lenUnit * 2,  depth},
                    .{lenUnit * 7,    lenUnit * 3,  depth},
                    .{lenUnit * 5,    lenUnit * 5,  depth},
                    .{lenUnit * 3.75, lenUnit * 5,  depth},
                    .{lenUnit * 5.75, lenUnit * 3,  depth},
                    .{lenUnit * 0,    lenUnit * 3,  depth},
                },
            },
        };
        const topology = [_][]const []const u32{
            &.{
                &.{0, 1, 15,  1, 14, 15,  1, 2, 3,  1, 3, 13,  3, 11, 12,  3, 4, 11,  4, 5, 10,  10, 5, 6,  9, 6, 7,  9, 7, 8}, //W
                &.{0, 1, 14,  0, 14, 15,  1, 2, 3,  1, 3, 4,  4, 11, 12,  4, 12, 13,  9, 10, 11,  9, 11, 5,  8, 9, 6,  8, 6, 7}, // S
                &.{1, 0, 13,  1, 13, 2,  2, 10, 9,  2, 9, 3,  3, 6, 5,  3, 5, 4,  11, 12, 7,  11, 7, 8}, // A
            },
            &.{
                &.{4, 0, 9,  4, 9, 5,  2, 1, 4,  2, 4, 3,  5, 8, 7,  5, 7, 6}, // UP ARROW
                &.{6, 0, 1,  6, 1, 5,  8, 9, 0,  8, 0, 7,  1, 2, 3,  1, 3, 4}, // DOWN ARROW
                &.{9, 0, 4,  9, 4, 5,  7, 8, 5,  7, 5, 6,  2, 3, 4,  2, 4, 1}, // RIGHT ARROW
            },
        };
        const color: cglm.vec4 = .{1.0, 1.0, 1.0, opacity};

        for (0..indicators.len) |i| {
            for (&indicators[i], 0..) |*indicator, j| {
                indicator.* = .{
                    .currStateIndex = 0,
                    .node           = .{
                        .mesh        = try Mesh.init(self.allocator),
                        .width       = width,
                        .height      = height,
                        .translation = undefined,
                        .depth       = depth,
                        .opacity     = opacity,
                    },
                };

                for (vertexPositions[i][j]) |pos| {
                    try indicator.node.mesh.appendVertex(.{
                        .pos   = pos,
                        .color = color,
                    });
                }

                for (topology[i][j]) |index| {
                    try indicator.node.mesh.appendIndex(index);
                }
            }
        }
        self.updateControlIndicatorPositions(indicators, paddleWidth, paddleHeight);
    }

    fn updatePaddlePositions(self: *GameLayer, paddles: []Paddle) void {
        paddles[0].setTranslation(
            .{
                self.worldWidth * 0.05,
                paddles[0].node.translation[1],
            },
            self.collisionHandler.epsilon,
        );
        paddles[1].setTranslation(
            .{
                self.worldWidth * 0.95 - paddles[1].node.width,
                paddles[1].node.translation[1],
            },
            self.collisionHandler.epsilon,
        );
    }

    fn updateCenterLinePosition(self: *GameLayer, centerLine: *CenterLine) void {
        for (centerLine.nodes.items) |*node| {
            node.translation[0] = self.worldWidth / 2.0 - node.width / 2.0;
        }
    }

    fn updateScorePositions(self: *GameLayer, scores: []Score) void {
        self.initializeScorePositions(scores);
    }

    fn initializeScorePositions(self: *GameLayer, scores: []Score) void {
        const scoreWidth   = scores[0].nodes[0].width;
        const scoreLenUnit = scoreWidth / 4;
        const scoreHeight  = scoreWidth * 2 - scoreLenUnit;

        const offsetLeft  = self.worldWidth / 2.0 - scoreWidth * 3;
        const offsetRight = self.worldWidth / 2.0 + scoreWidth * 2;
        const offsetUp    = self.worldHeight * 0.95 - scoreHeight;
        const translations = [_][]const cglm.vec2{
            &.{
                .{                            offsetLeft, offsetUp + scoreHeight - scoreLenUnit},
                .{offsetLeft + scoreWidth - scoreLenUnit,  offsetUp + scoreWidth - scoreLenUnit},
                .{offsetLeft + scoreWidth - scoreLenUnit,                              offsetUp},
                .{                            offsetLeft,                              offsetUp},
                .{                            offsetLeft,                              offsetUp},
                .{                            offsetLeft,  offsetUp + scoreWidth - scoreLenUnit},
                .{                            offsetLeft,  offsetUp + scoreWidth - scoreLenUnit},
            },
            &.{
                .{                            offsetRight, offsetUp + scoreHeight - scoreLenUnit},
                .{offsetRight + scoreWidth - scoreLenUnit,  offsetUp + scoreWidth - scoreLenUnit},
                .{offsetRight + scoreWidth - scoreLenUnit,                              offsetUp},
                .{                            offsetRight,                              offsetUp},
                .{                            offsetRight,                              offsetUp},
                .{                            offsetRight,  offsetUp + scoreWidth - scoreLenUnit},
                .{                            offsetRight,  offsetUp + scoreWidth - scoreLenUnit},
            },
        };

        for (0..scores.len) |i| {
            for (0..scores[i].nodes.len) |j| {
                scores[i].nodes[j].translation = translations[i][j];
            }
        }
    }

    fn updateControlIndicatorPositions(
        self:         *GameLayer,
        indicators:   *[PlayerManager.PLAYER_COUNT][3]ControlIndicator,
        paddleWidth:  f32,
        paddleHeight: f32,
    ) void {
        const indicatorHeight  = indicators[0][0].node.height;
        const indicatorLenUnit = indicatorHeight / 7;

        const offsetUp     = self.worldHeight * 0.5 + paddleHeight;
        const offsetDown   = self.worldHeight * 0.5 - paddleHeight - indicatorHeight;
        const offsetMiddle = self.worldHeight * 0.5 - indicatorHeight / 2;
        const offsetLeft   = self.worldWidth * 0.05 - indicatorLenUnit / 2;
        const offsetRight  = self.worldWidth * 0.95 - paddleWidth - indicatorLenUnit / 2;

        const translations = [_][]const cglm.vec2{
            &.{
                .{                         offsetLeft,     offsetUp},
                .{                         offsetLeft,   offsetDown},
                .{offsetLeft - indicatorHeight * 1.25, offsetMiddle},
            },
            &.{
                .{                         offsetRight,     offsetUp},
                .{                         offsetRight,   offsetDown},
                .{offsetRight + indicatorHeight * 1.25, offsetMiddle},
            },
        };

        for (0..indicators.len) |i| {
            for (0..indicators[i].len) |j| {
                indicators[i][j].node.translation = translations[i][j];
            }
        }
    }

    fn updateBallSpeed(self: *GameLayer, ctx: *ThreadContextRuntime) void {
        self.worldEntityManager.ball[ctx.threadStates.currGameIndex.load(.acquire)].speed = self.worldWidth * 0.8;
    }

    fn updateParticleSize(self: *GameLayer) void {
        self.particleManager.particleSize = self.worldHeight * 0.002;
    }

    fn updateCollisionHandler(self: *GameLayer) void {
        const epsilon = self.particleManager.particleSize + cfg.GENERAL_PURPOSE_EPSILON / 2.0;

        self.collisionHandler.worldBoundingBox.setTo(.{0.0, 0.0}, self.worldWidth, self.worldHeight, -epsilon);
        self.collisionHandler.epsilon = epsilon;
    }
};
