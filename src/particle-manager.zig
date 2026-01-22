const cglm = @import("bindings/cglm.zig").cglm;
const vk   = @import("bindings/vulkan.zig").vk;

const cfg = @import("config.zig");

const std = @import("std");

const ThreadContextComptime = @import("thread-context.zig").ThreadContextComptime;
const Particle              = @import("particle.zig").Particle;
const Ball                  = @import("ball.zig").Ball;
const CollisionHandler      = @import("collision-handler.zig").CollisionHandler;
const BoundingBox           = @import("bounding-box.zig").BoundingBox;

pub const ParticleManager = struct {
    pub const PARTICLE_COUNT   = 2048;
    pub const SPAWN_DELTA_TIME = 0.001;

    particles:            [PARTICLE_COUNT]Particle = undefined,
    currIndex:            usize                    = 0,
    checkpoints:          [4]usize                 = [_]usize{0} ** 4,
    pendingParticleCount: usize                    = 0,

    particleSize: f32,

    prng: *const std.Random,

    pub fn deinit(self: *ParticleManager, ctx: *const ThreadContextComptime) void {
        _ = self;
        ctx.graphicsApiRelated.deinitParticlesResources(ctx.graphicsApiRelated.graphicsAPI);
    }

    pub inline fn scheduleParticlesVictory(
        self:             *ParticleManager,
        ball:             *Ball,
        collisionSide:    CollisionHandler.Side,
        worldBoundingBox: BoundingBox,
    ) !void {
        comptime std.debug.assert(collisionSide == .LEFT or collisionSide == .RIGHT);

        try self.scheduleParticlesVictoryInternal(ball, collisionSide, worldBoundingBox);
    }

    pub fn scheduleParticlesVictoryInternal(
        self:            *ParticleManager,
        ball:            *Ball,
        collisionSide:   CollisionHandler.Side,
        worldBoundingBox:BoundingBox,
    ) !void {
        var posX:             f32 = undefined;
        var posY:             f32 = undefined;
        var heightDispersion: f32 = undefined;
        var widthDispersion:  f32 = undefined;
        if (collisionSide == .LEFT) {
                posX             = worldBoundingBox.minX;
                posY             = 0.0;
                widthDispersion  = 0.0;
                heightDispersion = worldBoundingBox.maxY;
        } else {
                posX             = worldBoundingBox.maxX;
                posY             = 0.0;
                widthDispersion  = 0.0;
                heightDispersion = worldBoundingBox.maxY;
        }

        var finalVel: cglm.vec2 = undefined;
        finalVel[0] = ball.prevVelocity[0] * 4;
        finalVel[1] = ball.prevVelocity[1] * 2;

        const magnitude            = @sqrt(finalVel[0] * finalVel[0] + finalVel[1] * finalVel[1]);
        const particleCount: usize = @intFromFloat(@min(magnitude * 0.035, 200.0));


        try self.scheduleParticles(
            particleCount,
            posX,
            posY,
            widthDispersion,
            heightDispersion,
            finalVel,
            collisionSide,
        );
    }

    pub inline fn scheduleParticlesGoal(
        self:          *ParticleManager,
        ball:          *Ball,
        collisionSide: CollisionHandler.Side,
        epsilon:       f32,
    ) !void {
        comptime std.debug.assert(collisionSide == .LEFT or collisionSide == .RIGHT);

        try self.scheduleParticlesGoalInternal(ball, collisionSide, epsilon);
    }

    pub fn scheduleParticlesGoalInternal(
        self:          *ParticleManager,
        ball:          *Ball,
        collisionSide: CollisionHandler.Side,
        epsilon:       f32,
    ) !void {
        const shavedOffcurrBoundingBox = ball.currBoundingBox.getShavedOffBy(epsilon);
        const pushConstant             = epsilon;

        var posX:             f32 = undefined;
        var posY:             f32 = undefined;
        var heightDispersion: f32 = undefined;
        var widthDispersion:  f32 = undefined;
        if (collisionSide == .LEFT) {
                posX             = ball.currBoundingBox.minX - pushConstant;
                posY             = shavedOffcurrBoundingBox.minY;
                widthDispersion  = 0.0;
                heightDispersion = ball.node.height;
        } else {
                posX             = ball.currBoundingBox.maxX + pushConstant;
                posY             = shavedOffcurrBoundingBox.minY;
                widthDispersion  = 0.0;
                heightDispersion = ball.node.height;
        }

        const magnitude            = @sqrt(ball.currVelocity[0] * ball.currVelocity[0] + ball.currVelocity[1] * ball.currVelocity[1]);
        const particleCount: usize = @intFromFloat(@min(magnitude * 0.5, 50.0));

        try self.scheduleParticles(
            particleCount,
            posX,
            posY,
            widthDispersion,
            heightDispersion,
            ball.currVelocity,
            collisionSide,
        );
    }

    pub fn scheduleParticlesBounce(
        self:                  *ParticleManager,
        ball:                  *Ball,
        collisionSide:         CollisionHandler.Side,
        epsilon:               f32,
        generalPurposeEpsilon: f32,
    ) !void {
        const shavedOffcurrBoundingBox = ball.currBoundingBox.getShavedOffBy(epsilon);
        const pushConstant             = 0.5 * epsilon + 1.25 * generalPurposeEpsilon;

        var posX:             f32 = undefined;
        var posY:             f32 = undefined;
        var heightDispersion: f32 = undefined;
        var widthDispersion:  f32 = undefined;
        switch (collisionSide) {
            .UP    => {
                posX             = shavedOffcurrBoundingBox.minX;
                posY             = ball.currBoundingBox.maxY + pushConstant;
                widthDispersion  = ball.node.width;
                heightDispersion = 0.0;
            },
            .DOWN  => {
                posX             = shavedOffcurrBoundingBox.minX;
                posY             = ball.currBoundingBox.minY - pushConstant;
                widthDispersion  = ball.node.width;
                heightDispersion = 0.0;
            },
            .LEFT  => {
                posX             = ball.currBoundingBox.minX - pushConstant;
                posY             = shavedOffcurrBoundingBox.minY;
                widthDispersion  = 0.0;
                heightDispersion = ball.node.height;
            },
            .RIGHT => {
                posX             = ball.currBoundingBox.maxX + pushConstant;
                posY             = shavedOffcurrBoundingBox.minY;
                widthDispersion  = 0.0;
                heightDispersion = ball.node.height;
            },
        }

        const magnitude            = @sqrt(ball.currVelocity[0] * ball.currVelocity[0] + ball.currVelocity[1] * ball.currVelocity[1]);
        const particleCount: usize = @intFromFloat(@min(magnitude * 0.035, 20.0));

        try self.scheduleParticles(
            particleCount,
            posX,
            posY,
            widthDispersion,
            heightDispersion,
            ball.currVelocity,
            collisionSide,
        );
    }

    pub fn scheduleParticles(
        self:             *ParticleManager,
        particleCount:    usize,
        posX:             f32,
        posY:             f32,
        widthDispersion:  f32,
        heightDispersion: f32,
        velocity:         cglm.vec2,
        collisionSide:    CollisionHandler.Side,
    ) !void {
        for (0..particleCount) |_| {
            var modifierX: f32 = undefined;
            var modifierY: f32 = undefined;
            var dirX:      f32 = undefined;
            var dirY:      f32 = undefined;
            switch(collisionSide) {
                .UP, .DOWN    => {
                    modifierX = 0.2;
                    modifierY = 0.1;
                    dirX      = if (self.prng.intRangeAtMost(u1, 0, 1) == 1) 1.0 else -1.0;
                    dirY      = if (velocity[1] == 0.0) std.math.sign(velocity[0]) else std.math.sign(velocity[1]);
                },
                .LEFT, .RIGHT => {
                    modifierX = 0.1;
                    modifierY = 0.2;
                    dirX      = if (velocity[0] == 0.0) std.math.sign(velocity[1]) else std.math.sign(velocity[0]);
                    dirY      = if (self.prng.intRangeAtMost(u1, 0, 1) == 1) 1.0 else -1.0;
                },
            }

            const randMinVelX: f32 = @floatFromInt(self.prng.intRangeAtMost(u8, 5, 10));
            const randMinVelY: f32 = @floatFromInt(self.prng.intRangeAtMost(u8, 5, 10));
            const randFactorX      = 0.01 + 0.99 * std.math.clamp(self.prng.float(f32), 0.01, 0.99);
            const randFactorY      = 0.01 + 0.99 * std.math.clamp(self.prng.float(f32), 0.01, 0.99);
            const finalVelX        = (@max(@abs(velocity[0] * modifierX), randMinVelX)) * randFactorX * dirX;
            const finalVelY        = (@max(@abs(velocity[1] * modifierY), randMinVelY)) * randFactorY * dirY;

            const finalPosX = posX + widthDispersion * self.prng.float(f32);
            const finalPosY = posY + heightDispersion * self.prng.float(f32);

            var currParticle: Particle = undefined;
            currParticle.size                   = self.particleSize;
            currParticle.color                  = .{1.0, 1.0, 1.0, 1.0};
            currParticle.currVelocity           = .{finalVelX, finalVelY};
            currParticle.prevVelocityDeltaTimed = .{
                currParticle.currVelocity[0] * SPAWN_DELTA_TIME,
                currParticle.currVelocity[1] * SPAWN_DELTA_TIME
            };
            currParticle.position               = .{
                finalPosX - (currParticle.currVelocity[0] * SPAWN_DELTA_TIME) / 2.0,
                finalPosY - (currParticle.currVelocity[1] * SPAWN_DELTA_TIME) / 2.0
            };
            currParticle.currBoundingBox.setTo(currParticle.position, currParticle.size);
            currParticle.prevBoundingBox.setTo(
                .{
                    currParticle.position[0] - currParticle.prevVelocityDeltaTimed[0],
                    currParticle.position[1] - currParticle.prevVelocityDeltaTimed[1]
                },
                currParticle.size
            );

            self.particles[self.currIndex] = currParticle;

            self.currIndex = (self.currIndex + 1) % PARTICLE_COUNT;
        }

        self.pendingParticleCount += particleCount;
    }

    pub fn spawnScheduledParticles(
        self:          *ParticleManager,
        currGameIndex: usize,
        ctx:           *const ThreadContextComptime,
    ) void {
        if (self.pendingParticleCount == 0) {
            return;
        }

        const batchPrevIndex   = ((self.currIndex + PARTICLE_COUNT) - 1) % PARTICLE_COUNT;
        const batchStartIndex  = ((batchPrevIndex + PARTICLE_COUNT) - (self.pendingParticleCount - 1)) % PARTICLE_COUNT;
        const hasWrappedAround = batchPrevIndex < batchStartIndex;
        if (self.pendingParticleCount >= PARTICLE_COUNT) {
            self.checkpoints = [_]usize{0, self.particles.len, 0, 0};
        } else if (hasWrappedAround) {
            self.checkpoints = [_]usize{batchStartIndex, self.particles.len, 0, self.currIndex};
        } else {
            self.checkpoints = [_]usize{batchStartIndex, batchPrevIndex, 0, 0};
        }

        ctx.graphicsApiRelated.submitParticles(
            ctx.graphicsApiRelated.graphicsAPI,
            currGameIndex,
            @ptrCast(&self.particles),
            self.checkpoints,
            @sizeOf(@TypeOf(self.particles[0])),
        );

        self.checkpoints          = [_]usize{0} ** 4;
        self.pendingParticleCount = 0;
    }
};
