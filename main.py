"""
Sparkie - AS3000 Electrical Standards Assistant
Simple chat interface for Australian electricians
"""

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from typing import List, Dict, Optional
import uuid
import json
import time
import os
import logging
from pathlib import Path
from datetime import datetime

from app.sparkie_engine_v3 import SparkieEngineV3

# Import evaluation framework
from evaluation.interaction_logger import get_interaction_logger

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Get the directory where this script is located
BASE_DIR = Path(__file__).parent

# Initialize FastAPI
app = FastAPI(
    title="Sparkie - AS3000 Assistant",
    description="AI-powered assistant for Australian electricians using AS3000 standards",
    version="1.0.0"
)

# Static files and templates with absolute paths
static_dir = BASE_DIR / "static"
templates_dir = BASE_DIR / "templates"

# Ensure directories exist
static_dir.mkdir(exist_ok=True)
templates_dir.mkdir(exist_ok=True)

app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")
templates = Jinja2Templates(directory=str(templates_dir))

# Initialize chat engine (will be lazy loaded)
chat_engine = None

def get_chat_engine():
    global chat_engine
    if chat_engine is None:
        chat_engine = SparkieEngineV3(use_v3=True)
    return chat_engine

# Simple in-memory chat storage
active_sessions: Dict[str, List] = {}  # session_id -> chat_history

# Startup/shutdown for evaluation framework
@app.on_event("startup")
async def startup_event():
    """Initialize evaluation framework on startup"""
    # Note: Background worker disabled for initial testing
    # logger = get_interaction_logger()
    # await logger.start_worker()
    print("[OK] Evaluation framework ready (background worker disabled)")

@app.on_event("shutdown")
async def shutdown_event():
    """Gracefully shutdown evaluation framework"""
    # logger = get_interaction_logger()
    # await logger.stop_worker()
    print("[OK] Shutdown complete")

# Pydantic models
class ChatMessage(BaseModel):
    message: str
    session_id: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    session_id: str
    timestamp: str
    retrieval_time: float = 0
    generation_time: float = 0
    chunks_used: int = 0
    visual_content_count: int = 0
    visual_content: List[Dict] = []
    extracted_references: List[str] = []
    reference_validated: bool = False
    enriched_question: str = ""
    total_time: float = 0


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Main page - direct AS3000 chat interface."""
    return templates.TemplateResponse("sparkie_chat.html", {"request": request})

@app.post("/api/start-session", response_model=Dict)
async def start_session():
    """Start a new AS3000 chat session."""
    try:
        session_id = str(uuid.uuid4())

        # Initialize empty chat history
        active_sessions[session_id] = []

        welcome_message = "G'day! I'm Sparkie, your AS3000 electrical standards assistant. Ask me about wiring rules, safety requirements, cable sizing, or any electrical installation questions."

        # Add welcome message to history
        active_sessions[session_id].append({
            "role": "assistant",
            "content": welcome_message
        })

        # Log session creation to Snowflake
        try:
            logger.info("Logging new session to Snowflake...")
            from snowflake.snowpark import Session

            connection_params = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": os.getenv("SNOWFLAKE_DATABASE"),
                "schema": os.getenv("SNOWFLAKE_SCHEMA")
            }

            session_sf = Session.builder.configs(connection_params).create()

            # Insert session record - RAG_SESSION has: session_id, user_id, client_type, app_version, metadata, ts
            session_sf.sql(f"""
                INSERT INTO RAG_SESSION (session_id, client_type, app_version)
                SELECT '{session_id}', 'web', '1.0.0'
            """).collect()

            session_sf.close()
            logger.info(f"Logged session {session_id} to RAG_SESSION table")

        except Exception as log_error:
            logger.error(f"Failed to log session to Snowflake: {log_error}", exc_info=True)

        return {
            "status": "connected",
            "session_id": session_id,
            "welcome_message": welcome_message,
            "timestamp": datetime.now().isoformat()
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to start session: {str(e)}")

@app.post("/api/chat")
async def chat_endpoint(chat_req: ChatMessage):
    """Handle AS3000 electrician chat messages."""
    try:
        session_id = chat_req.session_id
        message = chat_req.message.strip()
        
        if not message:
            raise HTTPException(status_code=400, detail="Message cannot be empty")
        
        # Validate session
        if session_id not in active_sessions:
            raise HTTPException(status_code=404, detail="Session not found")
        
        chat_history = active_sessions[session_id]
        
        # Add user message to history
        chat_history.append({"role": "user", "content": message})
        
        # Generate response using Sparkie engine
        start_time = time.time()
        try:
            engine = get_chat_engine()
            result = engine.generate_response(chat_history, message)
            response_text = result["response"]
        except Exception as e:
            logger.error(f"Sparkie engine error: {e}", exc_info=True)
            print(f"Warning: Sparkie engine error: {e}")
            response_text = "I'm sorry, I'm having trouble accessing the AS3000 standards right now. Please try again or consult AS3000:2018 directly."
            result = {"response": response_text, "retrieval_time": 0, "generation_time": 0, "chunks_used": 0}
        
        total_time = time.time() - start_time
        
        # Add assistant response to history
        chat_history.append({"role": "assistant", "content": response_text})
        
        # Create comprehensive response with all debug data including new metadata
        response_data = {
            "response": response_text,
            "session_id": session_id,
            "timestamp": datetime.now().isoformat(),
            "retrieval_time": result.get("retrieval_time", 0),
            "generation_time": result.get("generation_time", 0),
            "chunks_used": result.get("chunks_used", 0),
            "visual_content_count": result.get("visual_content_count", 0),
            "visual_content": result.get("visual_content", []),
            "extracted_references": result.get("extracted_references", []),
            "reference_validated": result.get("reference_validated", False),
            "enriched_question": result.get("enriched_question", ""),
            "total_time": total_time,
            # NEW: Add detailed metadata for sidebar
            "chunks_metadata": result.get("chunks_metadata", []),
            "visual_metadata": result.get("visual_metadata", [])
        }

        # Log interaction to evaluation framework (simplified for testing)
        try:
            logger.info("Starting Snowflake logging for interaction...")
            from snowflake.snowpark import Session
            interaction_id = str(uuid.uuid4())

            connection_params = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": os.getenv("SNOWFLAKE_DATABASE"),
                "schema": os.getenv("SNOWFLAKE_SCHEMA")
            }
            logger.info(f"Connecting to Snowflake: {connection_params['database']}.{connection_params['schema']}")

            session_sf = Session.builder.configs(connection_params).create()
            logger.info("Snowflake session created successfully")

            # Enhanced insert with metadata
            import json
            metadata_dict = {
                'retrieval_time': result.get('retrieval_time', 0),
                'generation_time': result.get('generation_time', 0),
                'chunks_used': result.get('chunks_used', 0),
                'visual_content_count': result.get('visual_content_count', 0),
                'chunks_metadata': result.get('chunks_metadata', [])[:5],  # Store top 5 chunks for eval
                'visual_metadata': result.get('visual_metadata', []),  # Store ALL visual metadata (not truncated)
                'extracted_references': result.get('extracted_references', []),
                'reference_validated': result.get('reference_validated', False)
            }
            metadata_json = json.dumps(metadata_dict)

            model_name = 'meta-llama/llama-4-maverick-17b-128e-instruct'  # Your Groq model

            # Use TO_VARIANT to convert JSON string directly without parsing issues
            # First create a temp table with the JSON string, then INSERT with TO_VARIANT
            import uuid as uuid_lib
            temp_table = f"TEMP_INSERT_{uuid_lib.uuid4().hex[:8]}"

            # Extract times in milliseconds for separate columns
            retrieval_time_ms = result.get('retrieval_time', 0) * 1000
            generation_time_ms = result.get('generation_time', 0) * 1000

            # Debug logging to trace timing values
            logger.info(f"DEBUG: retrieval_time from result = {result.get('retrieval_time', 0)}")
            logger.info(f"DEBUG: generation_time from result = {result.get('generation_time', 0)}")
            logger.info(f"DEBUG: retrieval_time_ms = {retrieval_time_ms}")
            logger.info(f"DEBUG: generation_time_ms = {generation_time_ms}")

            # Create temp DataFrame with all values including JSON as string
            temp_df = session_sf.create_dataframe([[
                interaction_id, session_id, message, None, None, model_name,
                response_text[:1000], None, None, total_time * 1000, None,
                'success', None, metadata_json, retrieval_time_ms, generation_time_ms
            ]], schema=[
                'interaction_id', 'session_id', 'user_query', 'sanitized_query',
                'query_type', 'model_name', 'answer_text', 'answer_tokens',
                'prompt_tokens', 'latency_ms', 'total_cost_usd', 'status',
                'eval_run_id', 'metadata_json_str', 'retrieval_time_ms', 'generation_time_ms'
            ])

            # Write to temp table
            temp_df.write.mode('overwrite').save_as_table(temp_table, table_type='temp')

            # INSERT from temp table with PARSE_JSON for metadata
            session_sf.sql(f"""
                INSERT INTO RAG_INTERACTION (
                    interaction_id, session_id, ts, user_query, sanitized_query,
                    query_type, model_name, answer_text, answer_tokens,
                    prompt_tokens, latency_ms, total_cost_usd, status,
                    eval_run_id, metadata, retrieval_time_ms, generation_time_ms
                )
                SELECT
                    interaction_id, session_id, CURRENT_TIMESTAMP(), user_query, sanitized_query,
                    query_type, model_name, answer_text, answer_tokens,
                    prompt_tokens, latency_ms, total_cost_usd, status,
                    eval_run_id, PARSE_JSON(metadata_json_str), retrieval_time_ms, generation_time_ms
                FROM {temp_table}
            """).collect()

            # Drop temp table
            session_sf.sql(f"DROP TABLE IF EXISTS {temp_table}").collect()
            logger.info(f"Executed INSERT for interaction {interaction_id}")

            session_sf.close()
            response_data['interaction_id'] = interaction_id
            logger.info(f"Logged interaction {interaction_id} to Snowflake successfully")
        except Exception as log_error:
            logger.error(f"Failed to log interaction to Snowflake: {log_error}", exc_info=True)

        return response_data
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Chat error: {str(e)}")

@app.get("/api/session/{session_id}", response_model=Dict)
async def get_session_info(session_id: str):
    """Get session chat history."""
    if session_id not in active_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    return {
        "session_id": session_id,
        "chat_history": active_sessions[session_id]
    }


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.get("/debug")
async def debug_endpoint():
    """Debug endpoint to test server reload."""
    return {"message": "Debug endpoint working", "timestamp": datetime.now().isoformat()}

@app.get("/debug/snowflake")
async def debug_snowflake():
    """Test Snowflake connection and RAW_TEXT table access."""
    try:
        engine = get_chat_engine()
        engine._ensure_initialized()
        
        if engine.session:
            # Ensure we're using the correct warehouse
            engine.session.sql("USE WAREHOUSE ELECTRICAL_RAG_WH").collect()
            
            # Test RAW_TEXT table in correct database with correct column names
            result = engine.session.sql("SELECT COUNT(*) as row_count FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RAW_TEXT WHERE IS_VALID = TRUE").collect()
            row_count = result[0]['ROW_COUNT'] if result else 0
            
            return {
                "snowflake_connected": True,
                "warehouse": "ELECTRICAL_RAG_WH",
                "raw_text_table_exists": True,
                "valid_chunks": row_count,
                "timestamp": datetime.now().isoformat()
            }
        else:
            return {
                "snowflake_connected": False,
                "error": "Session is None",
                "timestamp": datetime.now().isoformat()
            }
    except Exception as e:
        return {
            "snowflake_connected": False,
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.get("/debug/raw-text")
async def debug_raw_text():
    """Show sample AS3000 content from RAW_TEXT table."""
    try:
        engine = get_chat_engine()
        engine._ensure_initialized()
        
        if engine.session:
            # Ensure correct warehouse
            engine.session.sql("USE WAREHOUSE ELECTRICAL_RAG_WH").collect()
            
            # Get sample chunks
            result = engine.session.sql("""
                SELECT 
                    LEFT(CHUNK, 150) as chunk_preview,
                    LEFT(LABEL, 100) as label_preview,
                    CHUNK_LENGTH
                FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RAW_TEXT 
                WHERE IS_VALID = TRUE
                ORDER BY GLOBAL_CHUNK_INDEX
                LIMIT 3
            """).collect()
            
            chunks = []
            for row in result:
                chunks.append({
                    "chunk_preview": row['CHUNK_PREVIEW'],
                    "label_preview": row['LABEL_PREVIEW'],
                    "chunk_length": row['CHUNK_LENGTH']
                })
            
            return {
                "sample_chunks": chunks,
                "timestamp": datetime.now().isoformat()
            }
        else:
            return {
                "error": "Snowflake session not available",
                "timestamp": datetime.now().isoformat()
            }
    except Exception as e:
        return {
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }


@app.get("/debug/test-query")
async def debug_test_query():
    """Test AS3000 query retrieval."""
    try:
        engine = get_chat_engine()
        engine._ensure_initialized()

        if engine.session:
            # Test a sample electrical query
            test_question = "What cable size for 32A circuit?"
            results = engine.retrieve_unified_content(test_question)

            return {
                "test_question": test_question,
                "results_found": len(results),
                "sample_result": {
                    "chunk_preview": results[0].TEXT_CONTENT[:200] if results else None,
                    "similarity": float(results[0].SIMILARITY) if results else None,
                    "content_type": results[0].CONTENT_TYPE if results else None,
                    "has_visual": results[0].VISUAL_URL is not None if results else False
                } if results else None,
                "timestamp": datetime.now().isoformat()
            }
        else:
            return {
                "error": "Snowflake session not available",
                "timestamp": datetime.now().isoformat()
            }
    except Exception as e:
        return {
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.get("/debug/content-types-raw-text")
async def debug_content_types():
    """Check what content types exist in RAW_TEXT table."""
    try:
        engine = get_chat_engine()
        engine._ensure_initialized()

        if engine.session:
            # Check content types in RAW_TEXT
            result = engine.session.sql("""
                SELECT
                    CONTENT_TYPE,
                    COUNT(*) as count
                FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RAW_TEXT
                WHERE IS_VALID = TRUE
                GROUP BY CONTENT_TYPE
                ORDER BY count DESC
            """).collect()

            content_types = []
            for row in result:
                content_types.append({
                    "content_type": row['CONTENT_TYPE'],
                    "count": row['COUNT']
                })

            return {
                "content_types_in_raw_text": content_types,
                "timestamp": datetime.now().isoformat()
            }
        else:
            return {
                "error": "Snowflake session not available",
                "timestamp": datetime.now().isoformat()
            }
    except Exception as e:
        return {
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.get("/api/image/{image_id}")
async def serve_image(image_id: str):
    """Serve images from Snowflake stage through FastAPI."""
    try:
        engine = get_chat_engine()
        engine._ensure_initialized()
        
        if engine.session:
            # Get the image data from Snowflake stage
            result = engine.session.sql(f"""
                SELECT GET_PRESIGNED_URL('@PUBLIC_IMAGES', 'public_images/{image_id}.png') as presigned_url
            """).collect()
            
            if result and result[0]['PRESIGNED_URL']:
                # For now, return the presigned URL for the client to fetch
                import requests
                response = requests.get(result[0]['PRESIGNED_URL'])
                
                if response.status_code == 200:
                    return Response(
                        content=response.content,
                        media_type="image/png",
                        headers={"Cache-Control": "public, max-age=3600"}
                    )
                    
            raise HTTPException(status_code=404, detail="Image not found")
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error serving image: {str(e)}")

@app.get("/test")
async def test_endpoint():
    """Test endpoint to verify server reload."""
    return {"message": "Server reloaded successfully!", "timestamp": datetime.now().isoformat()}

@app.post("/test-connect")
async def test_connect_simple(data: dict):
    """Test POST endpoint without Pydantic model."""
    return {"received": data, "timestamp": datetime.now().isoformat()}

# Cleanup old sessions periodically (simple implementation for pilot)
@app.on_event("startup")
async def startup_event():
    print("Sparkie AS3000 Assistant starting up...")
    print("FastAPI server ready for Australian electricians!")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)# Trigger reload
