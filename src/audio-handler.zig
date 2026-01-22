const ma   = @import("bindings//miniaudio.zig").ma;
const cglm = @import("bindings//cglm.zig").cglm;

const std = @import("std");

pub const AudioHandler = struct {
    pub const NUM_OF_BOUNCE_PIECES: u8 = 16;

    pub const Note = struct {
        timerStart: f32,
        timerCurr:  f32,
        phase:      f32,
        basePitch:  f32,
    };

    pub const BouncePiece = struct {
        note: Note,

        velocity: cglm.vec2,
    };

    const GoalPiece = struct {
        note: Note,

        velocity: cglm.vec2,
    };

    const VictoryPiece = struct {
        notes:         [2]Note,
        currNoteIndex: usize = 0,

        velocity: cglm.vec2
    };

    pub const SoundState = struct {
        bouncePieces:    [NUM_OF_BOUNCE_PIECES]BouncePiece,
        currBounceIndex: usize = 0,

        victoryPiece: VictoryPiece,

        goalPiece: GoalPiece,
    };

    device: ma.ma_device,

    state: SoundState,

    pub fn playGoal(self: *AudioHandler, velocity: cglm.vec2) void {
        const goalPiece = &self.state.goalPiece;

        goalPiece.note.timerCurr = goalPiece.note.timerStart;
        goalPiece.note.phase     = 0.0;
        goalPiece.velocity       = velocity;
    }

    pub fn playVictory(self: *AudioHandler, velocity: cglm.vec2) void {
        const notes = &self.state.victoryPiece.notes;

        notes[0].timerCurr = notes[0].timerStart;
        notes[0].phase     = 0.0;

        notes[1].timerCurr = notes[1].timerStart;
        notes[1].phase     = 0.0;

        self.state.victoryPiece.velocity = velocity;
    }

    pub fn playBounce(self: *AudioHandler, velocity: cglm.vec2) void {
        const bouncePiece = &self.state.bouncePieces[self.state.currBounceIndex];

        bouncePiece.note.timerCurr = self.state.bouncePieces[self.state.currBounceIndex].note.timerStart;
        bouncePiece.note.phase     = 0.0;
        bouncePiece.velocity       = velocity;
        self.state.currBounceIndex = (self.state.currBounceIndex + 1) % self.state.bouncePieces.len;
    }

    pub fn dataCallback(
        pDevice:    [*c]ma.ma_device,
        pOutput:    ?*anyopaque,
        pInput:     ?*const anyopaque,
        frameCount: ma.ma_uint32,
    ) callconv(.c) void {
        _ = pInput;

        const state: *SoundState = @alignCast(@ptrCast(@as(*ma.ma_device, pDevice).pUserData));
        var out:     [*]f32      = @alignCast(@ptrCast(pOutput));

        const samples: f32 = 48000.0;
        const deltaTime    = 1.0 / samples;

        const bounceAmplitude  = 0.25 / @as(f32, @floatFromInt(state.bouncePieces.len));
        const goalAmplitude    = bounceAmplitude;
        const victoryAmplitude = bounceAmplitude;

        for (0..frameCount) |i| {
            var sample: f32 = 0.0;

            for (&state.bouncePieces) |*bouncePiece| {
                const note = &bouncePiece.note;

                if (note.timerCurr <= 0.0) {
                    continue;
                }

                const velPitchOffset = @min(@abs(bouncePiece.velocity[0]) + @abs(bouncePiece.velocity[1]), note.basePitch);
                const frequency      = note.basePitch / 2 + velPitchOffset;
                note.phase += std.math.tau * frequency * deltaTime;

                const fadeOutTime = note.timerStart / 2;
                const envelope    = std.math.pow(f32, note.timerCurr / fadeOutTime, 2.0);
                sample += @sin(note.phase) * bounceAmplitude * envelope;

                note.timerCurr -= deltaTime;
            }

            if (state.goalPiece.note.timerCurr > 0.0) {
                const goalNote = &state.goalPiece.note;

                const velPitchOffset = @min(@abs(state.goalPiece.velocity[0]) + @abs(state.goalPiece.velocity[1]), goalNote.basePitch);
                const frequency      = goalNote.basePitch / 2 + velPitchOffset;
                goalNote.phase += std.math.tau * frequency * deltaTime;

                const fadeOutTime = goalNote.timerStart / 2;
                const envelope    = std.math.pow(f32, goalNote.timerCurr / fadeOutTime, 2.0);
                sample += @sin(goalNote.phase) * goalAmplitude * envelope;

                goalNote.timerCurr -= deltaTime;
            }

            for (&state.victoryPiece.notes) |*note| {
                if (note.timerCurr <= 0.0) {
                    continue;
                }

                const velPitchOffset = @min(@abs(state.victoryPiece.velocity[0]) + @abs(state.victoryPiece.velocity[1]), note.basePitch);
                const frequency      = note.basePitch / 2 + velPitchOffset;
                note.phase += std.math.tau * frequency * deltaTime;

                const fadeOutTime = note.timerStart / 2;
                const envelope    = std.math.pow(f32, note.timerCurr / fadeOutTime, 2.0);
                sample += @sin(note.phase) * victoryAmplitude * envelope;

                note.timerCurr -= deltaTime;

                break;
            }

            sample = std.math.tanh(sample * 2);

            out[i * 2]     = sample;
            out[i * 2 + 1] = sample;
        }
    }
};
