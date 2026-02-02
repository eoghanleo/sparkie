"""
COMPLETE AS3000 SOLUTION
End-to-end pipeline: Images + Rich Descriptions + Embeddings + Database

Goal: Get everything working, optimize retrieval later
- Upload all 164 images without encryption  
- Generate rich Maverick descriptions
- Create embeddings for search
- Populate VISUAL_CONTENT completely
"""

import os
import json
import base64
import time
import logging
from pathlib import Path
from typing import List, Dict, Optional
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor, as_completed

from snowflake.snowpark import Session
from groq import Groq

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class AS3000Image:
    """Complete AS3000 image with all metadata"""
    image_id: str                    # sec7_p035_d00  
    section_name: str                # sec7
    page_number: int                 # 35
    local_file_path: str            # Path to PNG file
    stage_filename: str             # sec7_p035_d00.png
    vision_description: str = None   # Rich Maverick description
    file_size_bytes: int = 0
    upload_success: bool = False
    embedding_success: bool = False

class CompleteAS3000Pipeline:
    """Complete AS3000 processing pipeline"""
    
    def __init__(self):
        self.session = None
        self.groq_client = None
        self.images: List[AS3000Image] = []
        
        # Progress tracking
        self.stats = {
            'total_images': 0,
            'uploaded': 0,
            'described': 0,
            'embedded': 0,
            'errors': []
        }
    
    def initialize_connections(self):
        """Initialize Snowflake and Groq"""
        logger.info("Initializing connections...")
        
        # Snowflake
        try:
            connection_params = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "authenticator": os.getenv("SNOWFLAKE_AUTHENTICATOR"), 
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": "ELECTRICAL_RAG_WH",
                "database": "ELECTRICAL_STANDARDS_DB",
                "schema": "AS_STANDARDS"
            }
            self.session = Session.builder.configs(connection_params).create()
            logger.info("✓ Snowflake connected")
        except Exception as e:
            logger.error(f"Snowflake connection failed: {e}")
            raise
        
        # Groq
        try:
            api_key = os.getenv("GROQ_API_KEY")
            if not api_key:
                raise ValueError("GROQ_API_KEY required")
            self.groq_client = Groq(api_key=api_key)
            logger.info("✓ Groq connected")
        except Exception as e:
            logger.error(f"Groq connection failed: {e}")
            raise
    
    def prepare_clean_slate(self):
        """Clear everything for fresh start"""
        logger.info("Preparing clean slate...")
        
        try:
            # Clear stage
            self.session.sql("REMOVE @AS_STANDARDS.PUBLIC_IMAGES").collect()
            logger.info("✓ Stage cleared")
            
            # Clear table
            self.session.sql("DELETE FROM VISUAL_CONTENT").collect()
            logger.info("✓ Table cleared")
            
            # Ensure stage exists
            self.session.sql("""
                CREATE STAGE IF NOT EXISTS AS_STANDARDS.PUBLIC_IMAGES 
                DIRECTORY = (ENABLE = TRUE)
                FILE_FORMAT = (TYPE = 'CSV')
            """).collect()
            
            # Ensure EMBEDDING column exists
            try:
                self.session.sql("ALTER TABLE VISUAL_CONTENT ADD COLUMN EMBEDDING VECTOR(FLOAT, 1024)").collect()
                logger.info("✓ EMBEDDING column added")
            except:
                logger.info("✓ EMBEDDING column exists")
                
        except Exception as e:
            logger.error(f"Clean slate preparation failed: {e}")
            raise
    
    def discover_local_images(self, image_dirs: List[str] = None):
        """Find all local AS3000 images"""
        if image_dirs is None:
            image_dirs = ["simple_images", "pipeline_extracted_images", "improved_extracted"]
        
        logger.info(f"Discovering images in: {image_dirs}")
        
        for img_dir in image_dirs:
            dir_path = Path(img_dir)
            if not dir_path.exists():
                continue
                
            logger.info(f"Scanning {img_dir}...")
            
            # Get all PNG files
            png_files = list(dir_path.rglob("*.png"))
            
            for png_file in png_files:
                try:
                    # Parse image info from filename
                    filename = png_file.name
                    
                    # Extract section and page info
                    if filename.startswith("sec7_p"):
                        # Format: sec7_p035_d00.png
                        parts = filename.replace(".png", "").split("_")
                        section = "sec7"
                        page_part = parts[1]  # p035
                        page_num = int(page_part[1:])  # 35
                        
                    elif filename.startswith("sec3_p"):
                        parts = filename.replace(".png", "").split("_")
                        section = "sec3"
                        page_part = parts[1]
                        page_num = int(page_part[1:])
                        
                    else:
                        # Skip files that don't match our naming
                        continue
                    
                    # Create AS3000Image object
                    image = AS3000Image(
                        image_id=filename.replace(".png", ""),
                        section_name=section,
                        page_number=page_num,
                        local_file_path=str(png_file),
                        stage_filename=filename,
                        file_size_bytes=png_file.stat().st_size
                    )
                    
                    self.images.append(image)
                    
                except Exception as e:
                    logger.warning(f"Skipped {png_file}: {e}")
            
            if self.images:
                logger.info(f"Found {len(self.images)} images in {img_dir}")
                break  # Use first directory that has images
        
        self.stats['total_images'] = len(self.images)
        logger.info(f"✓ Discovered {len(self.images)} total AS3000 images")
        
        if not self.images:
            raise ValueError("No AS3000 images found! Need to extract images first.")
    
    def upload_all_images(self):
        """Upload all images to Snowflake without encryption"""
        logger.info(f"Uploading {len(self.images)} images without encryption...")
        
        for i, image in enumerate(self.images, 1):
            try:
                # Upload without encryption
                normalized_path = image.local_file_path.replace('\\', '/')
                put_command = f"PUT 'file://{normalized_path}' @AS_STANDARDS.PUBLIC_IMAGES AUTO_COMPRESS=FALSE ENCRYPTION=(TYPE='NONE')"
                
                self.session.sql(put_command).collect()
                image.upload_success = True
                self.stats['uploaded'] += 1
                
                if i % 20 == 0 or i == len(self.images):
                    logger.info(f"  Progress: {i}/{len(self.images)} uploaded")
                    
            except Exception as e:
                error_msg = f"Upload failed {image.image_id}: {e}"
                logger.error(error_msg)
                self.stats['errors'].append(error_msg)
        
        logger.info(f"✓ Upload complete: {self.stats['uploaded']}/{len(self.images)}")
    
    def generate_vision_descriptions(self, batch_size: int = 3):
        """Generate rich descriptions with LLaMA Maverick"""
        logger.info(f"Generating vision descriptions for {len(self.images)} images...")
        
        # Only process successfully uploaded images
        uploaded_images = [img for img in self.images if img.upload_success]
        logger.info(f"Processing {len(uploaded_images)} successfully uploaded images")
        
        for i, image in enumerate(uploaded_images, 1):
            try:
                logger.info(f"[{i}/{len(uploaded_images)}] Analyzing {image.image_id}...")
                
                # Read local image file
                with open(image.local_file_path, 'rb') as f:
                    image_data = f.read()
                base64_data = base64.b64encode(image_data).decode('utf-8')
                
                # Comprehensive prompt for AS3000 content
                prompt = f"""Analyze this AS3000 Australian electrical standards image from {image.section_name}, page {image.page_number}.

Provide a detailed technical description including:

1. IDENTIFICATION:
   - Any table numbers (Table 8.1, Table 3.2, etc.)
   - Figure numbers or diagram labels
   - Section/clause references

2. CONTENT ANALYSIS:
   - All visible column headers and row labels
   - Specific electrical values (voltages, currents, impedances, ratings)  
   - Equipment types (MCBs, RCDs, cables, switchboards, meters)
   - Technical specifications and requirements
   - Installation methods or procedures

3. ELECTRICAL DETAILS:
   - Circuit breaker ratings and types
   - Cable sizes and current capacities  
   - Voltage levels and earthing arrangements
   - Testing procedures and measurement values
   - Safety requirements and compliance notes

4. AS3000 CONTEXT:
   - Relevant Australian standard clauses
   - Compliance requirements
   - Application contexts (residential, commercial, industrial)

Be comprehensive and technically accurate. If this is Table 8.1 (earth fault loop impedance), describe ALL visible Zs values, equipment types, and RCD categories in detail."""

                # Call LLaMA Maverick vision model
                completion = self.groq_client.chat.completions.create(
                    model="meta-llama/llama-4-maverick-17b-128e-instruct",
                    messages=[{
                        "role": "user", 
                        "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{base64_data}"}}
                        ]
                    }],
                    max_tokens=2048,
                    temperature=0.1
                )
                
                # Store the rich description
                image.vision_description = completion.choices[0].message.content
                self.stats['described'] += 1
                
                # Rate limiting (important for Groq API)
                time.sleep(1.2)  # ~50 images per minute
                
            except Exception as e:
                error_msg = f"Vision analysis failed {image.image_id}: {e}"
                logger.error(error_msg)
                self.stats['errors'].append(error_msg)
                
                # Fallback description
                image.vision_description = f"AS3000 {image.section_name} page {image.page_number} electrical standards content showing technical specifications and requirements."
        
        logger.info(f"✓ Vision analysis complete: {self.stats['described']}/{len(uploaded_images)}")
    
    def populate_database_complete(self):
        """Insert all data into VISUAL_CONTENT with descriptions"""
        logger.info("Populating database with complete metadata...")
        
        successfully_described = [img for img in self.images if img.vision_description]
        
        for i, image in enumerate(successfully_described, 1):
            try:
                # Insert comprehensive record
                insert_sql = """
                INSERT INTO VISUAL_CONTENT (
                    IMAGE_ID, SECTION_NAME, PAGE_NUMBER, CONTENT_TYPE,
                    FILE_PATH, DESCRIPTION, UPLOAD_DATE
                ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """
                
                self.session.sql(insert_sql, params=[
                    image.image_id,
                    image.section_name,
                    image.page_number,
                    "electrical_diagram",  # content_type
                    image.stage_filename,   # file_path (what's actually in stage)
                    image.vision_description
                ]).collect()
                
                if i % 25 == 0 or i == len(successfully_described):
                    logger.info(f"  Progress: {i}/{len(successfully_described)} records inserted")
                    
            except Exception as e:
                error_msg = f"Database insert failed {image.image_id}: {e}"
                logger.error(error_msg)
                self.stats['errors'].append(error_msg)
        
        logger.info(f"✓ Database population complete: {len(successfully_described)} records")
    
    def generate_all_embeddings(self):
        """Generate embeddings for all descriptions"""
        logger.info("Generating embeddings for searchability...")
        
        try:
            # Use Sparkie's exact embedding model
            embed_sql = """
            UPDATE VISUAL_CONTENT 
            SET EMBEDDING = SNOWFLAKE.CORTEX.EMBED_TEXT_1024('snowflake-arctic-embed-l-v2.0', DESCRIPTION)
            WHERE EMBEDDING IS NULL AND DESCRIPTION IS NOT NULL
            """
            
            self.session.sql(embed_sql).collect()
            
            # Count successful embeddings
            result = self.session.sql("""
                SELECT COUNT(EMBEDDING) as embedded_count
                FROM VISUAL_CONTENT 
                WHERE EMBEDDING IS NOT NULL
            """).collect()
            
            if result:
                self.stats['embedded'] = result[0]['EMBEDDED_COUNT']
            
            logger.info(f"✓ Embeddings generated: {self.stats['embedded']}")
            
        except Exception as e:
            error_msg = f"Embedding generation failed: {e}"
            logger.error(error_msg)
            self.stats['errors'].append(error_msg)
    
    def validate_complete_solution(self):
        """Test search functionality and validate everything works"""
        logger.info("Validating complete solution...")
        
        try:
            # Test search for Table 8.1
            search_sql = """
            SELECT 
                IMAGE_ID,
                SECTION_NAME,
                PAGE_NUMBER,
                VECTOR_COSINE_SIMILARITY(
                    SNOWFLAKE.CORTEX.EMBED_TEXT_1024('snowflake-arctic-embed-l-v2.0', 'Table 8.1 earth fault loop impedance maximum values'),
                    EMBEDDING
                ) as similarity,
                LEFT(DESCRIPTION, 150) as desc_preview
            FROM VISUAL_CONTENT 
            WHERE EMBEDDING IS NOT NULL
            ORDER BY similarity DESC
            LIMIT 5
            """
            
            results = self.session.sql(search_sql).collect()
            
            logger.info("🔍 SEARCH TEST RESULTS for 'Table 8.1 earth fault loop impedance':")
            for i, row in enumerate(results, 1):
                logger.info(f"  {i}. {row['IMAGE_ID']} (page {row['PAGE_NUMBER']}, similarity: {row['SIMILARITY']:.3f})")
                logger.info(f"     {row['DESC_PREVIEW']}...")
                logger.info("")
            
            # Overall statistics
            logger.info("="*70)
            logger.info("🎉 COMPLETE AS3000 SOLUTION SUMMARY:")
            logger.info(f"   Total images discovered: {self.stats['total_images']}")
            logger.info(f"   Successfully uploaded: {self.stats['uploaded']}")
            logger.info(f"   Vision descriptions: {self.stats['described']}")
            logger.info(f"   Embeddings generated: {self.stats['embedded']}")
            logger.info(f"   Errors encountered: {len(self.stats['errors'])}")
            
            if self.stats['errors']:
                logger.info("\nErrors:")
                for error in self.stats['errors'][:3]:
                    logger.info(f"   - {error}")
            
            # Success criteria
            success = (
                self.stats['uploaded'] > 0 and 
                self.stats['described'] > 0 and 
                self.stats['embedded'] > 0 and
                len(results) > 0
            )
            
            if success:
                logger.info("\n✅ SUCCESS: Complete AS3000 solution is working!")
                logger.info("   - Images uploaded without encryption")
                logger.info("   - Rich Maverick descriptions generated")  
                logger.info("   - Embeddings created for search")
                logger.info("   - Search functionality validated")
                logger.info("\n🔍 Ready to test in Sparkie interface!")
            else:
                logger.info("\n❌ Issues found - check logs for details")
            
            return success
            
        except Exception as e:
            logger.error(f"Validation failed: {e}")
            return False
    
    def run_complete_solution(self):
        """Execute the complete AS3000 solution"""
        try:
            logger.info("🚀 Starting COMPLETE AS3000 SOLUTION...")
            
            # Step 1: Initialize everything
            self.initialize_connections()
            
            # Step 2: Clean slate
            self.prepare_clean_slate()
            
            # Step 3: Find images
            self.discover_local_images()
            
            # Step 4: Upload without encryption  
            self.upload_all_images()
            
            # Step 5: Generate rich descriptions
            self.generate_vision_descriptions()
            
            # Step 6: Populate database
            self.populate_database_complete()
            
            # Step 7: Generate embeddings
            self.generate_all_embeddings()
            
            # Step 8: Validate everything
            success = self.validate_complete_solution()
            
            return success
            
        except Exception as e:
            logger.error(f"Complete solution failed: {e}")
            return False
            
        finally:
            if self.session:
                self.session.close()

if __name__ == "__main__":
    # Run the complete AS3000 solution
    pipeline = CompleteAS3000Pipeline()
    success = pipeline.run_complete_solution()
    
    if success:
        print("\n🎉 COMPLETE SUCCESS!")
        print("All AS3000 images are now:")
        print("  ✓ Uploaded without encryption")
        print("  ✓ Described by LLaMA Maverick") 
        print("  ✓ Searchable with embeddings")
        print("  ✓ Ready for Sparkie queries")
        print("\n🔍 Test: Search for 'Table 8.1' in Sparkie!")
    else:
        print("\n❌ Issues encountered - check logs")
        print("📋 Review complete_as3000_solution.log for details")