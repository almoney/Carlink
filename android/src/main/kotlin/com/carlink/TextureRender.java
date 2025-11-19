package com.carlink;

/**
   * TextureRender - OpenGL ES 2.0 Video Frame Renderer
   *
   * Renders hardware-decoded H.264 video frames from the CPC200-CCPA adapter to the display
   * using OpenGL ES 2.0 with external OES textures for optimal performance.
   *
   * Key responsibilities:
   * - Compiles and manages vertex/fragment shaders for video texture rendering
   * - Draws decoded video frames as fullscreen quad using triangle strip geometry
   * - Handles GL_TEXTURE_EXTERNAL_OES textures from MediaCodec hardware decoder
   * - Provides runtime fragment shader replacement for video effects/corrections
   * - Manages OpenGL state initialization and error checking
   *
   * Workflow:
   * 1. Constructor accepts texture ID and initializes vertex buffer geometry
   * 2. surfaceCreated() compiles shaders after EGL context is available
   * 3. drawFrame() renders the latest SurfaceTexture frame to current surface
   * 4. checkGlError() validates GL operations and handles critical errors
   *
   * Integration: Used by OutputSurface to render MediaCodec output frames in the
   * video playback pipeline for CarPlay/Android Auto Projection.
   *
   * Performance: Uses hardware-accelerated external textures with efficient
   * single-pass rendering. Targets Android API 32+ with OpenGL ES 2.0.
   *
   * Based on Android Open Source Project's GLSurfaceView rendering patterns.
   */
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

import android.graphics.SurfaceTexture;
import android.opengl.GLES11Ext;
import android.opengl.GLES20;
import android.opengl.Matrix;
import android.util.Log;

/**
 * Code for rendering a texture onto a surface using OpenGL ES 2.0.
 */
class TextureRender {
    private static final String TAG = "CARLINK";
    private static final int FLOAT_SIZE_BYTES = 4;
    private static final int TRIANGLE_VERTICES_DATA_STRIDE_BYTES = 5 * FLOAT_SIZE_BYTES;
    private static final int TRIANGLE_VERTICES_DATA_POS_OFFSET = 0;
    private static final int TRIANGLE_VERTICES_DATA_UV_OFFSET = 3;
    private final float[] mTriangleVerticesData = {
            // X, Y, Z, U, V
            -1.0f, -1.0f, 0, 0.f, 0.f,
            1.0f, -1.0f, 0, 1.f, 0.f,
            -1.0f,  1.0f, 0, 0.f, 1.f,
            1.0f,  1.0f, 0, 1.f, 1.f,
    };
    private FloatBuffer mTriangleVertices;
    private static final String VERTEX_SHADER =
            "uniform mat4 uMVPMatrix;\n" +
                    "uniform mat4 uSTMatrix;\n" +
                    "attribute vec4 aPosition;\n" +
                    "attribute vec4 aTextureCoord;\n" +
                    "varying vec2 vTextureCoord;\n" +
                    "void main() {\n" +
                    "  gl_Position = uMVPMatrix * aPosition;\n" +
                    "  vTextureCoord = (uSTMatrix * aTextureCoord).xy;\n" +
                    "}\n";
    private static final String FRAGMENT_SHADER =
            "#extension GL_OES_EGL_image_external : require\n" +
                    "precision mediump float;\n" +      // highp here doesn't seem to matter
                    "varying vec2 vTextureCoord;\n" +
                    "uniform samplerExternalOES sTexture;\n" +
                    "void main() {\n" +
                    "  gl_FragColor = texture2D(sTexture, vTextureCoord);\n" +
                    "}\n";
    private float[] mMVPMatrix = new float[16];
    private float[] mSTMatrix = new float[16];
    private int mProgram;
    private int mTextureID = -12345;
    private int muMVPMatrixHandle;
    private int muSTMatrixHandle;
    private int maPositionHandle;
    private int maTextureHandle;

    // State management for proper error handling
    private boolean mIsInitialized = false;

    public TextureRender(int textureId) {
        mTextureID = textureId;

        mTriangleVertices = ByteBuffer.allocateDirect(
                        mTriangleVerticesData.length * FLOAT_SIZE_BYTES)
                .order(ByteOrder.nativeOrder()).asFloatBuffer();
        mTriangleVertices.put(mTriangleVerticesData).position(0);
        Matrix.setIdentityM(mSTMatrix, 0);
    }
    public int getTextureId() {
        return mTextureID;
    }
    public void drawFrame(SurfaceTexture st) {
        if (!mIsInitialized) {
            Log.w(TAG, "Skipping frame - OpenGL not initialized");
            return;
        }

        checkGlError("onDrawFrame start");
        st.getTransformMatrix(mSTMatrix);
        GLES20.glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
        GLES20.glClear(GLES20.GL_DEPTH_BUFFER_BIT | GLES20.GL_COLOR_BUFFER_BIT);
        GLES20.glUseProgram(mProgram);
        checkGlError("glUseProgram");
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, mTextureID);
        mTriangleVertices.position(TRIANGLE_VERTICES_DATA_POS_OFFSET);
        GLES20.glVertexAttribPointer(maPositionHandle, 3, GLES20.GL_FLOAT, false,
                TRIANGLE_VERTICES_DATA_STRIDE_BYTES, mTriangleVertices);
        checkGlError("glVertexAttribPointer maPosition");
        GLES20.glEnableVertexAttribArray(maPositionHandle);
        checkGlError("glEnableVertexAttribArray maPositionHandle");
        mTriangleVertices.position(TRIANGLE_VERTICES_DATA_UV_OFFSET);
        GLES20.glVertexAttribPointer(maTextureHandle, 2, GLES20.GL_FLOAT, false,
                TRIANGLE_VERTICES_DATA_STRIDE_BYTES, mTriangleVertices);
        checkGlError("glVertexAttribPointer maTextureHandle");
        GLES20.glEnableVertexAttribArray(maTextureHandle);
        checkGlError("glEnableVertexAttribArray maTextureHandle");
        Matrix.setIdentityM(mMVPMatrix, 0);
        GLES20.glUniformMatrix4fv(muMVPMatrixHandle, 1, false, mMVPMatrix, 0);
        GLES20.glUniformMatrix4fv(muSTMatrixHandle, 1, false, mSTMatrix, 0);
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
        checkGlError("glDrawArrays");
        GLES20.glFinish();
    }
    /**
     * Initializes GL state.  Call this after the EGL surface has been created and made current.
     */
    public void surfaceCreated() {
        try {
            mProgram = createProgram(VERTEX_SHADER, FRAGMENT_SHADER);
            if (mProgram == 0) {
                throw new RuntimeException("Failed creating OpenGL program");
            }

            if (!initializeProgramHandles()) {
                throw new RuntimeException("Failed initializing program handles");
            }

            // Configure texture parameters
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, mTextureID);
            checkGlError("glBindTexture mTextureID");
            GLES20.glTexParameterf(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER,
                    GLES20.GL_NEAREST);
            GLES20.glTexParameterf(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER,
                    GLES20.GL_LINEAR);
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S,
                    GLES20.GL_CLAMP_TO_EDGE);
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T,
                    GLES20.GL_CLAMP_TO_EDGE);
            checkGlError("glTexParameter");

            mIsInitialized = true;
            Log.d(TAG, "OpenGL surface initialized successfully");

        } catch (Exception e) {
            Log.e(TAG, "OpenGL initialization failed", e);
            mIsInitialized = false;
            cleanupGLResources();
        }
    }

    private boolean initializeProgramHandles() {
        maPositionHandle = GLES20.glGetAttribLocation(mProgram, "aPosition");
        checkGlError("glGetAttribLocation aPosition");
        if (maPositionHandle == -1) {
            Log.e(TAG, "Could not get attrib location for aPosition");
            return false;
        }

        maTextureHandle = GLES20.glGetAttribLocation(mProgram, "aTextureCoord");
        checkGlError("glGetAttribLocation aTextureCoord");
        if (maTextureHandle == -1) {
            Log.e(TAG, "Could not get attrib location for aTextureCoord");
            return false;
        }

        muMVPMatrixHandle = GLES20.glGetUniformLocation(mProgram, "uMVPMatrix");
        checkGlError("glGetUniformLocation uMVPMatrix");
        if (muMVPMatrixHandle == -1) {
            Log.e(TAG, "Could not get uniform location for uMVPMatrix");
            return false;
        }

        muSTMatrixHandle = GLES20.glGetUniformLocation(mProgram, "uSTMatrix");
        checkGlError("glGetUniformLocation uSTMatrix");
        if (muSTMatrixHandle == -1) {
            Log.e(TAG, "Could not get uniform location for uSTMatrix");
            return false;
        }

        return true;
    }

    private void cleanupGLResources() {
        if (mProgram != 0) {
            GLES20.glDeleteProgram(mProgram);
            mProgram = 0;
        }
        // Reset handles to invalid state
        maPositionHandle = -1;
        maTextureHandle = -1;
        muMVPMatrixHandle = -1;
        muSTMatrixHandle = -1;
    }
    /**
     * Replaces the fragment shader.
     */
    public void changeFragmentShader(String fragmentShader) {
        int newProgram = createProgram(VERTEX_SHADER, fragmentShader);
        if (newProgram != 0) {
            // Success - replace old program
            GLES20.glDeleteProgram(mProgram);
            mProgram = newProgram;

            // Re-initialize handles with new program
            if (!initializeProgramHandles()) {
                Log.e(TAG, "Failed to initialize handles for new fragment shader");
                mIsInitialized = false;
                cleanupGLResources();
            }
        } else {
            Log.e(TAG, "Failed creating program with custom fragment shader - keeping existing");
        }
    }
    private int loadShader(int shaderType, String source) {
        int shader = GLES20.glCreateShader(shaderType);
        checkGlError("glCreateShader type=" + shaderType);
        GLES20.glShaderSource(shader, source);
        GLES20.glCompileShader(shader);
        int[] compiled = new int[1];
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0);
        if (compiled[0] == 0) {
            Log.e(TAG, "Could not compile shader " + shaderType + ":");
            Log.e(TAG, " " + GLES20.glGetShaderInfoLog(shader));
            GLES20.glDeleteShader(shader);
            shader = 0;
        }
        return shader;
    }
    private int createProgram(String vertexSource, String fragmentSource) {
        int vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource);
        if (vertexShader == 0) {
            return 0;
        }
        int pixelShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
        if (pixelShader == 0) {
            return 0;
        }
        int program = GLES20.glCreateProgram();
        checkGlError("glCreateProgram");
        if (program == 0) {
            Log.e(TAG, "Could not create program");
        }
        GLES20.glAttachShader(program, vertexShader);
        checkGlError("glAttachShader");
        GLES20.glAttachShader(program, pixelShader);
        checkGlError("glAttachShader");
        GLES20.glLinkProgram(program);
        int[] linkStatus = new int[1];
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0);
        if (linkStatus[0] != GLES20.GL_TRUE) {
            Log.e(TAG, "Could not link program: ");
            Log.e(TAG, GLES20.glGetProgramInfoLog(program));
            GLES20.glDeleteProgram(program);
            program = 0;
        }
        return program;
    }
    public void checkGlError(String op) {
        // Only check GL errors in debug builds for performance optimization
        // According to Android OpenGL best practices, glGetError() calls are expensive
        if (true) {
            int error;
            while ((error = GLES20.glGetError()) != GLES20.GL_NO_ERROR) {
                String errorMsg = op + ": glError " + error + " (" + getGlErrorString(error) + ")";
                Log.e(TAG, errorMsg);

                // Handle critical GL_OUT_OF_MEMORY errors for video rendering
                if (error == GLES20.GL_OUT_OF_MEMORY) {
                    Log.e(TAG, "Critical GL_OUT_OF_MEMORY - video rendering may be compromised");
                    mIsInitialized = false; // Mark as uninitialized to prevent further rendering
                }
            }
        }
    }

    private String getGlErrorString(int error) {
        switch (error) {
            case GLES20.GL_INVALID_ENUM: return "GL_INVALID_ENUM";
            case GLES20.GL_INVALID_VALUE: return "GL_INVALID_VALUE";
            case GLES20.GL_INVALID_OPERATION: return "GL_INVALID_OPERATION";
            case GLES20.GL_OUT_OF_MEMORY: return "GL_OUT_OF_MEMORY";
            case GLES20.GL_INVALID_FRAMEBUFFER_OPERATION: return "GL_INVALID_FRAMEBUFFER_OPERATION";
            default: return "UNKNOWN_ERROR";
        }
    }
}
