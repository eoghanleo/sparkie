"""
COMPREHENSIVE AS3000 PIPELINE
Consolidates all fragmented efforts into one complete solution.

Pipeline Flow:
1. PyMuPDF extraction with improved settings (high-res, better detection)
2. LLaMA Maverick vision analysis for accurate descriptions  
3. Snowflake stage upload with proper organization
4. VISUAL_CONTENT database population with metadata
5. Embedding generation for enhanced retrieval
6. Validation and quality control throughout

This script replaces all previous fragmented approaches with a clean, 
end-to-end solution that ensures data consistency and quality.
"""

import fitz  # PyMuPDF
import os
import json
import base64
import time
import logging
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed
import asyncio
from dataclasses import dataclass

# Snowflake and AI imports
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark import Session
from groq import Groq
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('as3000_pipeline.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

load_dotenv()

@dataclass
class ExtractedImage:
    """Data structure for extracted image with metadata"""
    file_path: str
    image_id: str
    section_name: str
    page_number: int
    drawing_index: int
    width: int
    height: int
    file_size_bytes: int
    extraction_method: str  # 'full_page', 'drawing_region', 'table_detection'
    bbox: Optional[Tuple[float, float, float, float]] = None
    
    # Populated during pipeline
    vision_description: Optional[str] = None
    stage_file_path: Optional[str] = None
    public_url: Optional[str] = None
    embedding_vector: Optional[List[float]] = None

class AS3000Pipeline:
    """Comprehensive AS3000 processing pipeline"""
    
    def __init__(self):
        self.snowflake_session = None
        self.groq_client = None
        self.extracted_images: List[ExtractedImage] = []
        self.processing_stats = {
            'images_extracted': 0,
            'images_analyzed': 0,
            'images_uploaded': 0,
            'images_inserted': 0,
            'embeddings_generated': 0,
            'errors': []
        }
        
    def initialize_connections(self):
        """Initialize Snowflake and Groq connections"""
        logger.info("Initializing connections...")
        
        # Initialize Snowflake
        try:
            self.snowflake_session = get_active_session()
            logger.info("Using active Snowflake session")
        except:
            connection_parameters = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "authenticator": os.getenv("SNOWFLAKE_AUTHENTICATOR"),
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": "ELECTRICAL_RAG_WH",
                "database": "ELECTRICAL_STANDARDS_DB",
                "schema": "AS_STANDARDS"
            }
            self.snowflake_session = Session.builder.configs(connection_parameters).create()
            logger.info("Created new Snowflake session")
        
        # Initialize Groq
        groq_api_key = os.getenv("GROQ_API_KEY")
        if not groq_api_key:
            raise ValueError("GROQ_API_KEY not found in environment")
        
        self.groq_client = Groq(api_key=groq_api_key)
        logger.info("Groq client initialized")
        
        # Set Snowflake context
        self.snowflake_session.sql("USE WAREHOUSE ELECTRICAL_RAG_WH").collect()
        self.snowflake_session.sql("USE DATABASE ELECTRICAL_STANDARDS_DB").collect()  
        self.snowflake_session.sql("USE SCHEMA AS_STANDARDS").collect()
        logger.info("Snowflake context set")

    def extract_images_from_pdf(self, pdf_path: str, output_dir: str = "pipeline_extracted_images") -> List[ExtractedImage]:
        """
        Enhanced PyMuPDF extraction with improved settings for complete tables
        """
        logger.info(f"Extracting images from: {Path(pdf_path).name}")
        
        # Create output directory
        section_dir = Path(output_dir) / Path(pdf_path).stem
        section_dir.mkdir(parents=True, exist_ok=True)
        
        extracted = []
        doc = fitz.open(pdf_path)
        
        # Get section name from filename
        section_name = Path(pdf_path).stem.replace("_pages_", "_P").replace("-", "_")
        
        for page_num in range(doc.page_count):
            page = doc[page_num]
            logger.info(f"Processing page {page_num + 1}/{doc.page_count}")
            
            # Method 1: High-resolution full page extraction (catches everything)
            try:
                # Ultra-high resolution for maximum detail
                mat = fitz.Matrix(4.0, 4.0)  # 4x zoom = 288 DPI
                pix = page.get_pixmap(matrix=mat)
                
                # Only save if page has substantial content
                if pix.width > 1000 and pix.height > 1000:
                    image_id = f"{section_name}_P{page_num+1:03d}_D00"
                    file_path = section_dir / f"{image_id}.png"
                    pix.save(str(file_path))
                    
                    extracted_image = ExtractedImage(
                        file_path=str(file_path),
                        image_id=image_id,
                        section_name=section_name,
                        page_number=page_num + 1,
                        drawing_index=0,
                        width=pix.width,
                        height=pix.height,
                        file_size_bytes=file_path.stat().st_size,
                        extraction_method='full_page'
                    )
                    extracted.append(extracted_image)
                    logger.info(f"  Extracted full page: {image_id}")
                    
            except Exception as e:
                logger.error(f"  Failed to extract full page {page_num+1}: {e}")
            
            # Method 2: Individual drawing/table extraction with improved detection
            try:
                drawings = page.get_drawings()
                if len(drawings) > 5:  # Likely contains tables/diagrams
                    
                    for draw_idx, drawing in enumerate(drawings[:8]):  # Top 8 drawings
                        rect = drawing.get("rect")
                        if not rect:
                            continue
                            
                        # Enhanced filtering for table-like content
                        width, height = rect.width, rect.height
                        area = width * height
                        aspect_ratio = width / height if height > 0 else 0
                        items = len(drawing.get("items", []))
                        
                        # Table detection heuristics (refined)
                        is_potential_table = (
                            area > 8000 and                    # Reasonable size
                            0.5 < aspect_ratio < 10.0 and      # Not extreme aspect ratio  
                            items > 8 and                      # Complex enough
                            width > 100 and height > 50        # Minimum dimensions
                        )
                        
                        if is_potential_table:
                            try:
                                # Extract at maximum resolution with padding
                                padded_rect = fitz.Rect(
                                    rect.x0 - 10, rect.y0 - 10,
                                    rect.x1 + 10, rect.y1 + 10
                                )
                                mat = fitz.Matrix(5.0, 5.0)  # Very high resolution
                                pix = page.get_pixmap(matrix=mat, clip=padded_rect)
                                
                                if pix.width > 100 and pix.height > 100:
                                    image_id = f"{section_name}_P{page_num+1:03d}_D{draw_idx+1:02d}"
                                    file_path = section_dir / f"{image_id}.png"
                                    pix.save(str(file_path))
                                    
                                    extracted_image = ExtractedImage(
                                        file_path=str(file_path),
                                        image_id=image_id,
                                        section_name=section_name,
                                        page_number=page_num + 1,
                                        drawing_index=draw_idx + 1,
                                        width=pix.width,
                                        height=pix.height,
                                        file_size_bytes=file_path.stat().st_size,
                                        extraction_method='table_detection',
                                        bbox=(rect.x0, rect.y0, rect.x1, rect.y1)
                                    )
                                    extracted.append(extracted_image)
                                    logger.info(f"  Extracted potential table: {image_id}")
                                    
                            except Exception as e:
                                logger.error(f"  Failed to extract drawing {draw_idx}: {e}")
                                
            except Exception as e:
                logger.error(f"  Drawing analysis failed for page {page_num+1}: {e}")
        
        doc.close()
        
        logger.info(f"Extraction complete: {len(extracted)} images from {Path(pdf_path).name}")
        self.processing_stats['images_extracted'] += len(extracted)
        return extracted

    def analyze_images_with_vision(self, images: List[ExtractedImage], batch_size: int = 5) -> None:
        """
        Analyze images with LLaMA Maverick vision model for accurate descriptions
        """
        logger.info(f"Starting vision analysis for {len(images)} images...")
        
        def analyze_single_image(image: ExtractedImage) -> bool:
            """Analyze a single image with vision model"""
            try:
                # Read and encode image
                with open(image.file_path, 'rb') as f:
                    image_data = f.read()
                base64_data = base64.b64encode(image_data).decode('utf-8')
                
                # Enhanced prompt for AS3000 electrical content
                prompt = f"""
                Analyze this AS3000 electrical standards image from {image.section_name}, page {image.page_number}.
                
                Describe EXACTLY what you see including:
                - Table numbers (e.g., Table 8.1, Table 3.2)  
                - Column headers and data
                - Electrical values (voltage, current, impedance, etc.)
                - Equipment types (MCBs, RCDs, cables, etc.)
                - Any calculations or formulas shown
                - Specific AS3000 standard references
                
                If this appears to be Table 8.1 (earth fault loop impedance), describe ALL visible values and equipment types in detail.
                Be specific about what electrical information is actually visible in the image.
                """
                
                # Call LLaMA Maverick vision model
                completion = self.groq_client.chat.completions.create(
                    model="meta-llama/llama-4-maverick-17b-128e-instruct",
                    messages=[{
                        "role": "user", 
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/png;base64,{base64_data}",
                                    "detail": "high"
                                }
                            }
                        ]
                    }],
                    temperature=0.2,
                    max_tokens=500
                )
                
                image.vision_description = completion.choices[0].message.content
                logger.info(f"  Vision analysis complete: {image.image_id}")
                return True
                
            except Exception as e:
                logger.error(f"  Vision analysis failed for {image.image_id}: {e}")
                self.processing_stats['errors'].append(f"Vision analysis failed: {image.image_id} - {str(e)}")
                return False
        
        # Process images in batches to respect rate limits
        for i in range(0, len(images), batch_size):
            batch = images[i:i + batch_size]
            logger.info(f"Processing vision batch {i//batch_size + 1} ({len(batch)} images)...")
            
            # Use threading for I/O bound vision API calls
            with ThreadPoolExecutor(max_workers=3) as executor:
                futures = [executor.submit(analyze_single_image, img) for img in batch]
                
                for future in as_completed(futures):
                    if future.result():
                        self.processing_stats['images_analyzed'] += 1
            
            # Rate limiting between batches
            if i + batch_size < len(images):
                time.sleep(2)  # Pause between batches
                
        logger.info(f"Vision analysis complete: {self.processing_stats['images_analyzed']}/{len(images)} successful")

    def upload_images_to_stage(self, images: List[ExtractedImage]) -> None:
        """
        Upload images to Snowflake stage with proper organization
        """
        logger.info(f"Uploading {len(images)} images to Snowflake stage...")
        
        try:
            # Create stage if not exists
            self.snowflake_session.sql("""
                CREATE STAGE IF NOT EXISTS AS_STANDARDS.PUBLIC_IMAGES 
                DIRECTORY = (ENABLE = TRUE)
                FILE_FORMAT = (TYPE = 'CSV')
            """).collect()
            
            for image in images:
                try:
                    # Use consistent naming: public_images/{IMAGE_ID}.png
                    stage_path = f"public_images/{image.image_id}.png"
                    
                    # Upload to stage using PUT command (convert Windows backslashes to forward slashes)
                    normalized_path = image.file_path.replace('\\', '/')
                    put_command = f"PUT 'file://{normalized_path}' @AS_STANDARDS.PUBLIC_IMAGES/{stage_path} AUTO_COMPRESS=FALSE"
                    self.snowflake_session.sql(put_command).collect()
                    
                    # Generate fresh presigned URL
                    url_result = self.snowflake_session.sql(
                        f"SELECT GET_PRESIGNED_URL('@AS_STANDARDS.PUBLIC_IMAGES', '{stage_path}') as URL"
                    ).collect()
                    
                    image.stage_file_path = stage_path
                    image.public_url = url_result[0]['URL'] if url_result else None
                    
                    logger.info(f"  Uploaded: {image.image_id}")
                    self.processing_stats['images_uploaded'] += 1
                    
                except Exception as e:
                    logger.error(f"  Upload failed for {image.image_id}: {e}")
                    self.processing_stats['errors'].append(f"Upload failed: {image.image_id} - {str(e)}")
        
        except Exception as e:
            logger.error(f"Stage upload setup failed: {e}")
            
        logger.info(f"Stage upload complete: {self.processing_stats['images_uploaded']} successful")

    def insert_into_visual_content(self, images: List[ExtractedImage]) -> None:
        """
        Insert image metadata and descriptions into VISUAL_CONTENT table
        """
        logger.info(f"Inserting {len(images)} records into VISUAL_CONTENT...")
        
        # Clear existing data (fresh start)
        try:
            self.snowflake_session.sql("DELETE FROM VISUAL_CONTENT").collect()
            logger.info("Cleared existing VISUAL_CONTENT data")
        except Exception as e:
            logger.warning(f"Failed to clear existing data: {e}")
        
        for image in images:
            if not image.vision_description:
                continue  # Skip images without vision analysis
                
            try:
                # Read image binary data
                with open(image.file_path, 'rb') as f:
                    binary_data = f.read()
                
                # Enhanced metadata extraction
                content_type = self._classify_content_type(image.vision_description)
                table_number = self._extract_table_number(image.vision_description)
                category = self._classify_content_category(image.vision_description)
                keywords = self._extract_technical_keywords(image.vision_description)
                title = self._generate_title(table_number, category, image.section_name)
                
                # Insert into database
                insert_sql = """
                    INSERT INTO VISUAL_CONTENT (
                        IMAGE_ID, SECTION_NAME, PAGE_NUMBER, DRAWING_INDEX,
                        IMAGE_DATA, FILE_PATH, DESCRIPTION, PUBLIC_URL,
                        CONTENT_TYPE, TABLE_NUMBER, TITLE, CONTENT_CATEGORY,
                        TECHNICAL_KEYWORDS, CREATED_AT
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """
                
                self.snowflake_session.sql(insert_sql, (
                    image.image_id,
                    image.section_name,
                    image.page_number,
                    image.drawing_index,
                    binary_data,
                    image.stage_file_path,
                    image.vision_description,
                    image.public_url,
                    content_type,
                    table_number,
                    title,
                    category,
                    keywords
                )).collect()
                
                logger.info(f"  Inserted: {image.image_id}")
                self.processing_stats['images_inserted'] += 1
                
            except Exception as e:
                logger.error(f"  Database insert failed for {image.image_id}: {e}")
                self.processing_stats['errors'].append(f"DB insert failed: {image.image_id} - {str(e)}")
        
        logger.info(f"Database insertion complete: {self.processing_stats['images_inserted']} records")

    def generate_embeddings(self) -> None:
        """
        Generate embeddings for vision descriptions to enable retrieval
        """
        logger.info("Generating embeddings for vision descriptions...")
        
        try:
            # Update embeddings for all descriptions
            update_sql = """
                UPDATE VISUAL_CONTENT 
                SET DESCRIPTION_EMBED = SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', DESCRIPTION)
                WHERE DESCRIPTION IS NOT NULL
                AND DESCRIPTION_EMBED IS NULL
            """
            
            result = self.snowflake_session.sql(update_sql).collect()
            
            # Get count of updated records
            count_result = self.snowflake_session.sql("""
                SELECT COUNT(*) as COUNT 
                FROM VISUAL_CONTENT 
                WHERE DESCRIPTION_EMBED IS NOT NULL
            """).collect()
            
            self.processing_stats['embeddings_generated'] = count_result[0]['COUNT']
            logger.info(f"Embedding generation complete: {self.processing_stats['embeddings_generated']} vectors")
            
        except Exception as e:
            logger.error(f"Embedding generation failed: {e}")
            self.processing_stats['errors'].append(f"Embedding generation failed: {str(e)}")

    def validate_pipeline_results(self) -> Dict:
        """
        Validate complete pipeline results and generate report
        """
        logger.info("Validating pipeline results...")
        
        validation_report = {
            'processing_stats': self.processing_stats,
            'data_quality': {},
            'table_81_status': {},
            'recommendations': []
        }
        
        try:
            # Check data quality
            quality_sql = """
                SELECT 
                    COUNT(*) as total_records,
                    COUNT(CASE WHEN DESCRIPTION IS NOT NULL THEN 1 END) as has_description,
                    COUNT(CASE WHEN DESCRIPTION_EMBED IS NOT NULL THEN 1 END) as has_embedding,
                    COUNT(CASE WHEN PUBLIC_URL IS NOT NULL THEN 1 END) as has_url,
                    COUNT(CASE WHEN TABLE_NUMBER IS NOT NULL THEN 1 END) as has_table_number
                FROM VISUAL_CONTENT
            """
            
            quality_result = self.snowflake_session.sql(quality_sql).collect()[0]
            validation_report['data_quality'] = dict(quality_result)
            
            # Check Table 8.1 specifically
            table_81_sql = """
                SELECT 
                    IMAGE_ID,
                    TABLE_NUMBER,
                    SUBSTR(DESCRIPTION, 1, 100) as description_preview,
                    CASE WHEN DESCRIPTION_EMBED IS NOT NULL THEN 'Yes' ELSE 'No' END as has_embedding
                FROM VISUAL_CONTENT
                WHERE TABLE_NUMBER = '8.1' OR DESCRIPTION ILIKE '%table 8.1%' OR DESCRIPTION ILIKE '%earth fault%'
                ORDER BY IMAGE_ID
            """
            
            table_81_results = self.snowflake_session.sql(table_81_sql).collect()
            validation_report['table_81_status'] = {
                'found_count': len(table_81_results),
                'images': [dict(row) for row in table_81_results]
            }
            
            # Generate recommendations
            if len(table_81_results) == 0:
                validation_report['recommendations'].append("⚠️  No Table 8.1 images found - check extraction settings")
            elif len(table_81_results) < 4:
                validation_report['recommendations'].append("⚠️  Expected 4 Table 8.1 images, found fewer - check PDF page 35")
            else:
                validation_report['recommendations'].append("✅ Table 8.1 images successfully processed")
            
            if self.processing_stats['errors']:
                validation_report['recommendations'].append(f"⚠️  {len(self.processing_stats['errors'])} errors occurred - check logs")
            else:
                validation_report['recommendations'].append("✅ Pipeline completed without errors")
                
        except Exception as e:
            logger.error(f"Validation failed: {e}")
            validation_report['validation_error'] = str(e)
        
        return validation_report

    def run_complete_pipeline(self, pdf_files: List[str]) -> Dict:
        """
        Execute the complete AS3000 processing pipeline
        """
        start_time = time.time()
        logger.info("="*80)
        logger.info("STARTING COMPREHENSIVE AS3000 PIPELINE")
        logger.info("="*80)
        
        try:
            # Step 1: Initialize connections
            self.initialize_connections()
            
            # Step 2: Extract images from all PDFs
            all_images = []
            for pdf_file in pdf_files:
                if Path(pdf_file).exists():
                    extracted = self.extract_images_from_pdf(pdf_file)
                    all_images.extend(extracted)
                    self.extracted_images.extend(extracted)
                else:
                    logger.error(f"PDF file not found: {pdf_file}")
                    
            logger.info(f"Total images extracted: {len(all_images)}")
            
            # Step 3: Vision analysis
            if all_images:
                self.analyze_images_with_vision(all_images)
            
            # Step 4: Upload to Snowflake stage  
            successful_analyses = [img for img in all_images if img.vision_description]
            if successful_analyses:
                self.upload_images_to_stage(successful_analyses)
            
            # Step 5: Insert into database
            successful_uploads = [img for img in successful_analyses if img.stage_file_path]
            if successful_uploads:
                self.insert_into_visual_content(successful_uploads)
            
            # Step 6: Generate embeddings
            if self.processing_stats['images_inserted'] > 0:
                self.generate_embeddings()
            
            # Step 7: Validation and reporting
            validation_report = self.validate_pipeline_results()
            
            # Final summary
            execution_time = time.time() - start_time
            logger.info("="*80)
            logger.info("PIPELINE EXECUTION COMPLETE")
            logger.info(f"Total execution time: {execution_time:.2f} seconds")
            logger.info(f"Images processed: {self.processing_stats['images_extracted']}")
            logger.info(f"Vision analyses: {self.processing_stats['images_analyzed']}")
            logger.info(f"Stage uploads: {self.processing_stats['images_uploaded']}")
            logger.info(f"Database inserts: {self.processing_stats['images_inserted']}")
            logger.info(f"Embeddings generated: {self.processing_stats['embeddings_generated']}")
            logger.info(f"Errors encountered: {len(self.processing_stats['errors'])}")
            logger.info("="*80)
            
            return validation_report
            
        except Exception as e:
            logger.error(f"Pipeline execution failed: {e}")
            return {"error": str(e), "processing_stats": self.processing_stats}

    # Helper methods for metadata extraction
    def _classify_content_type(self, description: str) -> str:
        desc_lower = description.lower()
        if 'table' in desc_lower:
            return 'table'
        elif any(word in desc_lower for word in ['diagram', 'drawing', 'schematic']):
            return 'diagram' 
        elif 'figure' in desc_lower:
            return 'figure'
        else:
            return 'table'  # Default for AS3000 content

    def _extract_table_number(self, description: str) -> Optional[str]:
        import re
        # Look for table numbers like "Table 8.1", "8.1", etc.
        matches = re.findall(r'table\s+(\d+\.\d+|\d+)', description.lower())
        if matches:
            return matches[0]
        
        # Look for standalone numbers that might be table numbers
        matches = re.findall(r'(\d+\.\d+)', description)
        if matches:
            return matches[0]
        
        return None

    def _classify_content_category(self, description: str) -> str:
        desc_lower = description.lower()
        if any(word in desc_lower for word in ['earth', 'earthing', 'fault', 'loop', 'impedance']):
            return 'earthing'
        elif any(word in desc_lower for word in ['mcb', 'circuit breaker', 'protection']):
            return 'protection'
        elif any(word in desc_lower for word in ['rcd', 'rcbo', 'earth leakage']):
            return 'rcd_protection'
        elif any(word in desc_lower for word in ['current', 'capacity', 'rating', 'conductor']):
            return 'current_rating'
        elif any(word in desc_lower for word in ['cable', 'installation', 'wiring']):
            return 'installation'
        else:
            return 'general'

    def _extract_technical_keywords(self, description: str) -> str:
        import re
        keywords = []
        
        # Extract electrical values
        voltage_matches = re.findall(r'\d+V|\d+\s*volts?', description, re.IGNORECASE)
        current_matches = re.findall(r'\d+A|\d+\s*amp[se]?|\d+\s*amperes?', description, re.IGNORECASE)
        keywords.extend(voltage_matches[:3])  # Limit to avoid overflow
        keywords.extend(current_matches[:3])
        
        # Common technical terms
        tech_terms = [
            'earth fault loop impedance', 'Zs', 'MCB', 'RCD', 'RCBO', 'TN system',
            'derating', 'coordination', 'selectivity', 'discrimination', 
            'fault current', '30mA', 'Type B', 'Type C', 'Type D'
        ]
        
        desc_lower = description.lower()
        for term in tech_terms:
            if term.lower() in desc_lower:
                keywords.append(term)
        
        return ', '.join(list(set(keywords)))  # Remove duplicates

    def _generate_title(self, table_number: Optional[str], category: str, section_name: str) -> str:
        if table_number:
            if table_number == '8.1':
                return f"Table {table_number} - Earth fault loop impedance values"
            elif table_number.startswith('3'):
                return f"Table {table_number} - Current carrying capacity requirements"
            else:
                return f"Table {table_number} - {category.replace('_', ' ').title()}"
        else:
            return f"{section_name} - {category.replace('_', ' ').title()}"


def main():
    """
    Main execution function - modify PDF files list as needed
    """
    # AS3000 PDF files to process
    pdf_files = [
        "as3000_parts/Section_7_Testing_verification_pages_500-599.pdf",  # Table 8.1 location
        "as3000_parts/Section_3_Selection_installation_wiring_systems_pages_150-211.pdf",  # Current capacity tables
        # Add more sections as needed
    ]
    
    pipeline = AS3000Pipeline()
    results = pipeline.run_complete_pipeline(pdf_files)
    
    # Save results
    with open("pipeline_results.json", "w") as f:
        json.dump(results, f, indent=2, default=str)
    
    print("\n" + "="*60)
    print("PIPELINE EXECUTION SUMMARY")
    print("="*60)
    print(json.dumps(results, indent=2, default=str))

if __name__ == "__main__":
    # NOTE: DO NOT EXECUTE - waiting for user approval
    print("Comprehensive AS3000 Pipeline ready for execution")
    print("Run main() to start the complete pipeline")